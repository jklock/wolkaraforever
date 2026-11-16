// WolkaraForever: dictation, in full.

#import "Dictation.h"
#import "AudioSessionCoordinator.h"
#import "../App/WolkaraForeverLog.h"
#import "../App/WKLocalization.h"
#import "VoiceSettings.h"
#import "KeyboardDictationEvents.h"

#import <AVFAudio/AVFAudio.h>
#import <Speech/Speech.h>
#import <UIKit/UIKit.h>
#include <math.h>

// kVK_Return, and the character the game expects for it. Taken from the accessory row,
// which sends its Return exactly this way.
static unsigned short const AKReturnKeyCode = 36;

// How long the recogniser gets to produce its last words after the audio ends.
//
// The capture records a file now and the recogniser reads the whole of it, so this is a whole-file pass
// rather than a streaming one, and it only starts once the audio has ended. This is the safety net for a
// stuck recogniser, not the expected wait - but a file request reports no partials, so a timeout that
// fired early would deliver nothing at all, which is the exact symptom that took days to separate from a
// silent microphone. Generous on purpose.
static NSTimeInterval const AKDefaultFinalizeTimeout = 8.0;

// Per capture, not per process: the loudest sample this capture has heard. Reset when a capture starts,
// so a second hold never reports the first hold's number.
static double AKLoudestSoFar;

// The same peak as a level in dBFS, because the linear value cannot show the difference that matters:
// a silent input meters at -120 dBFS, which is 0.000001 linear and looks like "not zero" to any check
// written as `> 0`. A room is -50 to -70 dBFS. Kept in decibels so the check can be a threshold that
// silence cannot satisfy.
static double AKLoudestDecibels = -160.0;

double AKVoiceLoudestDecibels(void) { return AKLoudestDecibels; }

double AKVoiceLoudestSample(void) { return AKLoudestSoFar; }

// The loudest sample a recording holds, as a level in dBFS, read from the recorder's own meter.
//
// The first version of this read the recorded file back with AVAudioFile and reported 0.00000 - which
// was the read failing with error -50, not the microphone being silent. A measurement that can fail and
// still look like the fault it is meant to detect is worse than no measurement, so the level comes from
// the recorder's meter, where silence is -160 dB and cannot be confused with a parse error.

#pragma mark - The real recogniser

// Owns the audio engine, the request and the task, because those three are one thing:
// the engine's tap is what feeds the request, and the request is what the task reads.
@interface AKSpeechSession : NSObject <AKDictationSpeech>
// Beyond the protocol: run the recognition half over a file that is already on disk. The
// self-test uses these so words can be proved to come back without a person speaking.
- (void)recogniseFile:(NSURL *)file;
- (void)recogniseFile:(NSURL *)file handler:(void (^)(NSString *text, BOOL isFinal, NSError *error))handler;
@end

// What every request this file makes has in common.
//
// Partials are asked for even though nothing is delivered from them. This is what the device
// said on 2026-10-22: with partial results switched off, the on-device recogniser took all
// 135,725 frames of a known sentence, was sent endAudio, and then called back *never* - no
// result and no error, for forty seconds. The app's delivery rule is unchanged and stays where
// it belongs: `speechReported:` ignores every non-final result, so a partial is a progress
// signal and nothing else.
//
// The dictation hint and punctuation are asked for only where this SDK and this system have
// them: both arrived in iOS 16, and a property sent to a system that has no such setter is a
// crash rather than a preference. They shape the recogniser's own output; no text is added here.
static void AKConfigureRecognitionRequest(SFSpeechRecognitionRequest *request,
                                          BOOL onDevice,
                                          NSArray<NSString *> *words) {
    request.requiresOnDeviceRecognition = onDevice;
    request.shouldReportPartialResults = YES;
    if (words.count) request.contextualStrings = words;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
    if (@available(iOS 16.0, *)) {
        request.taskHint = SFSpeechRecognitionTaskHintDictation;
        request.addsPunctuation = YES;
    }
#endif
}

@implementation AKSpeechSession {
    AVAudioEngine *_engine;
    BOOL _onDevice;
    NSArray<NSString *> *_words;
    SFSpeechRecognizer *_recognizer;
    SFSpeechRecognitionRequest *_request;
    SFSpeechRecognitionTask *_task;
    void (^_handler)(NSString *, BOOL, NSError *);
    BOOL _finished;
}

- (instancetype)init {
    if ((self = [super init])) {
        _recognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"en-US"]];
    }
    return self;
}

- (BOOL)isAvailable { return _recognizer.isAvailable; }
- (BOOL)supportsOnDeviceRecognition { return _recognizer.supportsOnDeviceRecognition; }

// Per language, because on-device recognition is: the SDK answers per recogniser, and a
// recogniser is per locale. Nil asks about the device's own language, which is what System
// means. A locale this iPad has no recogniser for is refused here, before the audio session is
// taken - the choice is not silently replaced by one that works.
- (BOOL)supportsOnDeviceRecognitionForLanguage:(nullable NSString *)language {
    SFSpeechRecognizer *recognizer = language
        ? [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:language]]
        : [[SFSpeechRecognizer alloc] init];
    return recognizer.supportsOnDeviceRecognition;
}

- (void)requestAuthorization:(void (^)(BOOL granted))completion {
    // A push-to-talk hold starts on the first syllable. Re-requesting permission
    // after it was already granted needlessly dispatches the real audio start to
    // a later turn of the main queue, so a quick “hello” is captured as only its
    // tail. Start immediately once iPadOS has already authorised this app.
    if (SFSpeechRecognizer.authorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized) {
        completion(YES);
        return;
    }
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(status == SFSpeechRecognizerAuthorizationStatusAuthorized);
        });
    }];
}

- (void)startOnDevice:(BOOL)onDevice
             language:(nullable NSString *)language
                words:(NSArray<NSString *> *)words
              handler:(void (^)(NSString *, BOOL, NSError *))handler {
    _handler = [handler copy];
    _finished = NO;

    _onDevice = onDevice;
    _words = [words copy];
    AKLoudestSoFar = 0;

    // The recogniser belongs to this capture, in this language.
    //
    // It used to be made once, in `-init`, for en-US, which is exactly why no other language
    // could ever work. Constructed here, a choice is honoured by the next hold and a change
    // cannot leak into a session that already started. Nil is the device's own language, which
    // is what System means.
    _recognizer = language
        ? [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:language]]
        : [[SFSpeechRecognizer alloc] init];
    if (!_recognizer) {
        NSError *refused = [NSError errorWithDomain:@"wolkaraforever.dictation" code:4 userInfo:@{
            NSLocalizedDescriptionKey: @"This iPad has no recogniser for that language."}];
        _finished = YES;
        if (_handler) _handler(@"", NO, refused);
        _handler = nil;
        return;
    }

    // One live Voice Processing I/O graph feeds recognition directly. There is no
    // recorder/file fallback: every controller edge gates buffers into this graph.
    SFSpeechAudioBufferRecognitionRequest *request = [SFSpeechAudioBufferRecognitionRequest new];
    AKConfigureRecognitionRequest(request, _onDevice, _words);
    _request = request;
    __weak AKSpeechSession *weakSelf = self;
    _task = [_recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        AKSpeechSession *session = weakSelf;
        if (!session || session->_finished) return;
        if (result.isFinal || error) session->_finished = YES;
        if (session->_handler) session->_handler(result.bestTranscription.formattedString ?: @"", result.isFinal, error);
    }];
    _engine = [AVAudioEngine new];
    AVAudioInputNode *input = _engine.inputNode;
    NSError *error = nil;
    AVAudioFormat *format = [input outputFormatForBus:0];
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        (void)when;
        [request appendAudioPCMBuffer:buffer];
    }];
    [_engine prepare];
    if (![_engine startAndReturnError:&error]) {
        [input removeTapOnBus:0];
        [self cancel];
        if (_handler) _handler(@"", NO, error);
        return;
    }
    WKLog("voice", @"dictation: streaming input started, %.0fHz %lu channel(s), session %@",
          format.sampleRate, (unsigned long)format.channelCount, AVAudioSession.sharedInstance.category);
}

- (void)finish {
    AVAudioInputNode *input = _engine.inputNode;
    [input removeTapOnBus:0];
    [_engine stop];
    _engine = nil;
    [(SFSpeechAudioBufferRecognitionRequest *)_request endAudio];
}

- (void)cancel {
    [_engine.inputNode removeTapOnBus:0];
    [_engine stop];
    _engine = nil;
    _finished = YES;
    _handler = nil;
    [_task cancel];
    _task = nil;
    _request = nil;
}

/// The recognition half on its own, for one file. Also the entry point the device self-test uses.
- (void)recogniseFile:(NSURL *)file handler:(void (^)(NSString *text, BOOL isFinal, NSError *error))handler {
    _handler = [handler copy];
    _finished = NO;
    _onDevice = YES;
    [self recogniseFile:file];
}

- (void)recogniseFile:(NSURL *)file {
    if (!file) return;
    // The file is fed to the recogniser as buffers, not handed over as a URL.
    //
    // Both are documented; only one of them has ever produced words on this device. The URL
    // request answers "No speech detected" about a third of a second after a 1.86s hold that
    // metered -24.8 dBFS - too fast to have listened to anything - while the streaming request
    // is the one the build that transcribed 21 characters into the game used. Feeding the file
    // we just wrote through the streaming request keeps that path and keeps the recording, so
    // the same audio can be re-run instead of re-spoken.
    SFSpeechAudioBufferRecognitionRequest *streaming = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    NSError *openError = nil;
    AVAudioFile *captured = [[AVAudioFile alloc] initForReading:file error:&openError];
    if (!captured || captured.length == 0) {
        // Nothing readable to stream: the URL request is still the honest last word, and it
        // will say what it thinks of the file. Whatever it answers, the log already carries
        // the byte and frame counts above.
        WKLog("voice", @"dictation: the recording is not readable as audio (%@), asking the recogniser about the file instead",
              openError.localizedDescription ?: @"no frames");
        SFSpeechURLRecognitionRequest *whole = [[SFSpeechURLRecognitionRequest alloc] initWithURL:file];
        AKConfigureRecognitionRequest(whole, _onDevice, _words);
        _request = whole;
    } else {
        AKConfigureRecognitionRequest(streaming, _onDevice, _words);
        _request = streaming;
    }

    __weak AKSpeechSession *weakSelf = self;
    _task = [_recognizer recognitionTaskWithRequest:_request
                                      resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        AKSpeechSession *session = weakSelf;
        if (!session || session->_finished) return;
        NSString *text = result.bestTranscription.formattedString ?: @"";
        // `isFinal` is the recogniser saying it has nothing more for this session.
        // That, or an error, is the moment the caller has been waiting for.
        if (result.isFinal || error) session->_finished = YES;
        if (session->_handler) session->_handler(text, result.isFinal, error);
    }];

    if (_request != streaming) return;
    // Fed off the main queue: a long hold is a longer read, and this runs while the game is
    // drawing. A fresh buffer per chunk because the request is documented to copy the audio it
    // is given, and a buffer that is only copied *sometimes* is the kind of assumption that
    // ends up as an intermittent half-sentence.
    NSURL *fileURL = file;
    AVAudioFrameCount chunk = 4096;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SFSpeechAudioBufferRecognitionRequest *request = streaming;
        NSError *readError = nil;
        AVAudioFile *file = [[AVAudioFile alloc] initForReading:fileURL error:&readError];
        if (!file) {
            WKLog("voice", @"dictation: the recording could not be opened for streaming: %@",
                  readError.localizedDescription ?: @"no reason");
            [request endAudio];
            return;
        }
        AVAudioFormat *format = file.processingFormat;
        AVAudioFramePosition total = file.length, fed = 0;
        while (fed < total) {
            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:chunk];
            if (!buffer) break;
            if (![file readIntoBuffer:buffer frameCount:chunk error:&readError]) break;
            if (buffer.frameLength == 0) break;
            [request appendAudioPCMBuffer:buffer];
            fed += (AVAudioFramePosition)buffer.frameLength;
        }
        [request endAudio];
        WKLog("voice", @"dictation: fed %lld of %lld frames (%.0fHz %luch%@) to the recogniser%@",
              fed, total, format.sampleRate, (unsigned long)format.channelCount,
              readError ? @"" : @"",
              readError ? [NSString stringWithFormat:@", read stopped: %@", readError.localizedDescription] : @"");
    });
}

@end

/// The recognition half, for a file somebody else recorded. See the declaration in Dictation.h for
/// why the app needs a way to test this without a person speaking.
void AKRecogniseDictationFile(NSURL *file, void (^completion)(NSString *_Nullable text, NSError *_Nullable error)) {
    if (!completion) return;
    AKSpeechSession *session = [AKSpeechSession new];
    if (!session.isAvailable) {
        completion(nil, [NSError errorWithDomain:@"wolkaraforever.dictation" code:2 userInfo:@{
            NSLocalizedDescriptionKey: @"Speech recognition is not available right now."}]);
        return;
    }
    if (!session.supportsOnDeviceRecognition) {
        completion(nil, [NSError errorWithDomain:@"wolkaraforever.dictation" code:3 userInfo:@{
            NSLocalizedDescriptionKey: @"This iPad cannot recognise speech on device."}]);
        return;
    }
    // Held until it answers. The recogniser task dies with the session that owns it, so a probe
    // whose session is a local - as the first version of this was - sends every frame, gets
    // endAudio, and is then deallocated before the recogniser can call back: no result, no error,
    // and forty seconds of a self-test waiting for a callback that can no longer arrive.
    static NSMutableArray<AKSpeechSession *> *probes;
    static NSLock *probesLock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ probes = [NSMutableArray array]; probesLock = [NSLock new]; });
    [probesLock lock]; [probes addObject:session]; [probesLock unlock];
    __block BOOL reported = NO;
    [session recogniseFile:file handler:^(NSString *text, BOOL isFinal, NSError *error) {
        // A partial result is not an answer, and an error is; whichever comes first ends this.
        if (!isFinal && !error) return;
        if (reported) return;
        reported = YES;
        [probesLock lock]; [probes removeObjectIdenticalTo:session]; [probesLock unlock];
        completion(error ? nil : text, error);
    }];
}

#pragma mark - The real audio session

// Takes the session and gives it back the way it was found. The old code set record
// mode and always left the app at playback, which is a change the game can hear.
@interface AKAudioSessionBridge : NSObject <AKDictationAudio>
- (void)beginRecordingAsync:(void (^)(BOOL ok, NSError *_Nullable error))completion;
@end

@implementation AKAudioSessionBridge

// The session is not this object's to take or to put back. The coordinator owns it, and this asks
// for a push-to-talk lease and hands it back. The answer is whether the session is in the state the
// policy says it should be in - not whether a call returned success, which is a different thing and
// is the one the old code reported while the microphone stayed held.
- (BOOL)beginRecording:(NSError **)error {
    return [[AKAudioSessionCoordinator shared] beginPushToTalk:error];
}
- (void)beginRecordingAsync:(void (^)(BOOL ok, NSError *_Nullable error))completion {
    [[AKAudioSessionCoordinator shared] beginPushToTalkAsync:completion];
}

- (BOOL)restore:(NSError **)error {
    return [[AKAudioSessionCoordinator shared] endPushToTalk:error];
}

@end

#pragma mark - Dictation

@implementation AKDictation {
    AKSpeechSession *_realSpeech;
    AKAudioSessionBridge *_realAudio;
    NSMutableString *_transcript;
    BOOL _delivered;
    BOOL _abandoned;
    // The capture belongs to the Chat Composer: partials are offered to its draft and the
    // result is never typed into the game.
    BOOL _composerCapture;
    NSUInteger _session;
    // The language this generation was started in, nil for System. Kept so a settings change
    // can tell an actual language change from the notification every other setting posts.
    NSString *_startedLanguage;
    // A partial result is a progress signal, not content; one line per generation is enough of
    // a record and keeps the log bounded.
    BOOL _loggedPartial;
}

+ (instancetype)shared {
    static AKDictation *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKDictation new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _transcript = [NSMutableString string];
        _finalizeTimeout = AKDefaultFinalizeTimeout;
        // The audio session is the coordinator's, and it says when push to talk was ended by an
        // interruption, a media reset or the route going. Dictation used to observe
        // AVAudioSessionInterruptionNotification itself, which is two owners of one session with two
        // ideas about it - what the review outcome's Phase 1 exists to remove.
        __weak AKDictation *weakSelf = self;
        [AKAudioSessionCoordinator shared].pushToTalkWasTaken = ^(NSString *why) {
            AKDictation *self2 = weakSelf;
            if (!self2) return;
            [self2 cancelBecause:@"interrupted"];
            void (^problem)(NSString *) = self2.problemHandler;
            if (problem) problem([NSString stringWithFormat:@"Something else took the audio (%@), so nothing was typed.", why]);
        };
        // And leaving the app does too. This matters here more than in most apps: the
        // target declares `UIBackgroundModes: [audio]` so a running game keeps its sound,
        // which means iOS does NOT take the session away when the user goes to the Home
        // screen. Without this, a session left listening would hold the microphone and
        // Apple's recogniser open in the background - the user would see the orange
        // indicator with the game behind it, and nothing would ever type the words.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appLeftTheForeground:)
                                                   name:UIApplicationDidEnterBackgroundNotification object:nil];
        // The speech language is a per-capture decision, so a change while the microphone is open
        // is answered here rather than being discovered on the next hold. It is also how the
        // feature being switched off reaches a session that is already running, whoever switched
        // it off.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged:)
                                                   name:AKVoiceSettingsDidChangeNotification object:nil];
    }
    return self;
}

- (void)appLeftTheForeground:(NSNotification *)note {
    (void)note;
    // Said before the state is changed, because the state is what a reader wants to know.
    WKLog("voice", @"dictation: the app went to the background (state=%ld, listening=%d)",
          (long)_state, (int)self.listening);
    if (_state == AKDictationStateIdle) return;
    [self cancelBecause:@"background"];
    void (^problem)(NSString *) = self.problemHandler;
    if (problem) problem(@"The app went to the background, so nothing was typed.");
}

// Any change to the settings, and the two that matter to a live session: the feature being
// turned off, and the language being changed.
//
// A language change cancels the old generation *before* the new one exists. That is the whole
// point: a recogniser that was asked for its last words can still call back, and the old
// generation's late final must never be delivered as the utterance that was spoken in the new
// language. Restarting is the same press continuing, so nothing here opens a chat box or
// synthesizes a key.
- (void)settingsChanged:(NSNotification *)note {
    (void)note;
    [AKAudioSessionCoordinator.shared setDictationEnabled:AKVoiceSettings.shared.enabled];
    AKVoiceSettings *settings = AKVoiceSettings.shared;
    if (!settings.enabled) {
        if (_state == AKDictationStateIdle) return;
        WKLog("voice", @"dictation: the feature was switched off with the microphone open");
        [self cancelBecause:@"disabled"];
        return;
    }
    if (_state != AKDictationStateAuthorizing && _state != AKDictationStateListening) return;
    NSString *wanted = settings.speechLanguageIdentifier;
    if (wanted == _startedLanguage) return;
    if ([wanted isEqualToString:_startedLanguage]) return;
    AKKDLog(@"recognizer.generation=%lu change=midcapture language=%@",
            (unsigned long)_session, wanted ?: @"system");
    [self cancelBecause:@"languageChange"];
    [self begin];
}

- (BOOL)listening { return _state == AKDictationStateListening || _state == AKDictationStateFinalizing; }

#pragma mark - The registered target

static __weak UIView *AKGameTextTarget = nil;

+ (void)setGameTextTarget:(nullable UIView *)view { AKGameTextTarget = view; }
+ (nullable UIView *)gameTextTarget { return AKGameTextTarget; }

#pragma mark - Seams

- (id<AKDictationSpeech>)speech {
    if (_speech) return _speech;
    if (!_realSpeech) _realSpeech = [AKSpeechSession new];
    return _realSpeech;
}

- (id<AKDictationAudio>)audio {
    if (_audio) return _audio;
    if (!_realAudio) _realAudio = [AKAudioSessionBridge new];
    return _realAudio;
}

#pragma mark - The one entry point

- (void)beginComposerCapture {
    // The Composer asks for the same capture the mapped button does; what differs is where the
    // words go. Nothing about the audio session or the recogniser changes.
    if (self.listening) {
        WKLog("voice", @"dictation: a Composer capture was asked for while one is already running; ignored");
        return;
    }
    _composerCapture = YES;
    WKLog("voice", @"dictation: capture for the Chat Composer");
    [self begin];
}

- (void)cancelComposerCapture {
    if (!_composerCapture) return;
    WKLog("voice", @"dictation: the Chat Composer asked for its capture to stop");
    [self cancel];
}

- (void)toggle {
    if (self.listening) [self end];
    else [self begin];
}

- (void)begin {
    switch (_state) {
    case AKDictationStateIdle: break;
    // Already busy: a second press while the microphone is opening is the same press.
    case AKDictationStateAuthorizing:
    case AKDictationStateListening:
    case AKDictationStateFinalizing: return;
    }
    _abandoned = NO;
    _delivered = NO;
    _loggedPartial = NO;
    [_transcript setString:@""];
    NSUInteger session = ++_session;
    [self setState:AKDictationStateAuthorizing];

    id<AKDictationSpeech> speech = self.speech;
    if (!speech.supportsOnDeviceRecognition) {
        [self fail:@"This iPad cannot recognise speech without sending it away, so the microphone stays off."
            reason:@"unavailable"];
        return;
    }
    // The chosen language, checked before the microphone is taken. A language this iPad has no
    // on-device recogniser for falls back to System for this hold - which is the recognition
    // behaviour that existed before the choice did - and says so, rather than opening a
    // microphone it cannot feed or silently believing it is listening in the chosen language.
    NSString *language = AKVoiceSettings.shared.speechLanguageIdentifier;
    if (![speech supportsOnDeviceRecognitionForLanguage:language]) {
        if (!language) {
            [self fail:@"This iPad cannot recognise speech without sending it away, so the microphone stays off."
                reason:@"unavailable"];
            return;
        }
        AKKDLog(@"failure reason=languageUnavailable fallback=system language=%@", language);
        void (^problem)(NSString *) = self.problemHandler;
        if (problem) problem(WKLocalizedFormat(@"voice.language.unavailable", language));
        language = nil;
        if (![speech supportsOnDeviceRecognitionForLanguage:nil]) {
            [self fail:@"This iPad cannot recognise speech without sending it away, so the microphone stays off."
                reason:@"unavailable"];
            return;
        }
    }
    _startedLanguage = [language copy];
    AKKDLog(@"recognizer.generation=%lu change=start language=%@",
            (unsigned long)session, language ?: @"system");
    __weak AKDictation *weakSelf = self;
    [speech requestAuthorization:^(BOOL granted) {
        AKDictation *self2 = weakSelf;
        if (!self2 || self2->_session != session) return;   // a later press replaced this
        AKKDLog(@"permission=%@", granted ? @"granted" : @"denied");
        if (!granted) {
            [self2 fail:@"Speech recognition permission was refused." reason:@"permission"];
            return;
        }
        [self2 startAudioForSession:session];
    }];
}

- (void)startAudioForSession:(NSUInteger)session {
    if (_session != session || _abandoned) return;
    // Refused before anything is opened, rather than started and failed: the audio
    // session is not ours to take if there is nothing to feed it to.
    if (!self.speech.isAvailable) {
        [self fail:@"Speech recognition is not available right now." reason:@"unavailable"];
        return;
    }

    id<AKDictationAudio> audio = self.audio;
    __weak AKDictation *weakSelf = self;
    void (^started)(BOOL, NSError *) = ^(BOOL ok, NSError *error) {
        AKDictation *self2 = weakSelf;
        if (!self2 || self2->_session != session || self2->_state != AKDictationStateAuthorizing) {
            // The button may have been released while AVAudioSession was activating. The
            // bridge, not a potentially deallocated dictation object, owns that lease.
            if (ok) [audio restore:NULL];
            return;
        }
        if (!ok) { [self2 fail:[NSString stringWithFormat:@"The audio session would not start: %@", error.localizedDescription] reason:@"audio"]; return; }
        [self2.speech startOnDevice:YES language:self2->_startedLanguage words:AKVoiceSettings.shared.customWords
                       handler:^(NSString *transcript, BOOL isFinal, NSError *error2) {
        [weakSelf speechReported:transcript isFinal:isFinal error:error2 session:session];
    }];
    [self2 setState:AKDictationStateListening];
    WKLog("voice", @"dictation: listening (on-device=1, language=%@)", self2->_startedLanguage ?: @"system");
    AKKDLog(@"recognizer.language=%@", self2->_startedLanguage ?: @"system");
    AKKDLog(@"recognizer.session.start generation=%lu language=%@ ondevice=1",
            (unsigned long)session, self2->_startedLanguage ?: @"system");
    };
    if ([self.audio isKindOfClass:AKAudioSessionBridge.class]) [(AKAudioSessionBridge *)self.audio beginRecordingAsync:started];
    else { NSError *error = nil; started([self.audio beginRecording:&error], error); }
}

// Read once, so a recogniser that is unavailable right now is refused rather than
// started and failed.
- (void)end {
    switch (_state) {
    case AKDictationStateIdle:
    case AKDictationStateFinalizing: return;
    case AKDictationStateAuthorizing:
        // Nothing was started. Abandon it, in case the permission answer arrives late.
        _abandoned = YES;
        AKKDLog(@"recognizer.session.end generation=%lu outcome=cancel", (unsigned long)_session);
        _session++;
        [self setState:AKDictationStateIdle];
        return;
    case AKDictationStateListening:
        break;
    }
    [self setState:AKDictationStateFinalizing];
    NSUInteger session = _session;
    [self.speech finish];
    // The recogniser is asked for its last words and given a bounded wait. Whichever
    // happens first, delivery happens once.
    __weak AKDictation *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.finalizeTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AKDictation *self2 = weakSelf;
        if (!self2 || self2->_state != AKDictationStateFinalizing || self2->_session != session) return;
        [self2 abandonForTimeout];
    });
}

// The deadline passed. Nothing is delivered.
//
// What is in hand is a *partial* result, and the product's promise is a final transcript:
// putting half a sentence into the game's chat box - and, with auto-submit on, sending it
// - is worse than putting nothing there. The remediation review caught the first version
// doing exactly that and calling it a timeout. The user is told instead, and because a
// timeout is usually the recogniser being unavailable or the microphone being silent,
// saying so is more useful than a guess at what they said.
- (void)abandonForTimeout {
    if (_state != AKDictationStateFinalizing) return;
    WKLog("voice", @"dictation: no final result within %.1fs; nothing will be typed", self.finalizeTimeout);
    AKKDLog(@"failure reason=timeout generation=%lu", (unsigned long)_session);
    AKKDLog(@"recognizer.session.end generation=%lu outcome=timeout", (unsigned long)_session);
    [self.speech cancel];
    [self giveTheSessionBack];
    _abandoned = YES;
    _delivered = YES;   // nothing may be delivered for this session
    _session++;
    BOOL composer = _composerCapture;
    _composerCapture = NO;
    [self setState:AKDictationStateIdle];
    if (composer) [self composeEvent:@"failure" text:nil reason:@"no result in time"];
    void (^problem)(NSString *) = self.problemHandler;
    if (problem) problem(@"The recogniser did not finish in time, so nothing was typed.");
}

- (void)cancel { [self cancelBecause:@"cancel"]; }

// Every way a session can end without words goes through here, so the generation is spent and
// the bounded record says why. `outcome` is one of the enumerated values in
// KeyboardDictationEvents.h; it is never free-form.
- (void)cancelBecause:(NSString *)outcome {
    if (_state != AKDictationStateIdle) {
        AKKDLog(@"recognizer.session.end generation=%lu outcome=%@",
                (unsigned long)_session, outcome ?: @"cancel");
    }
    _abandoned = YES;
    _delivered = YES;   // nothing may be delivered after a cancel
    _session++;
    [self.speech cancel];
    [self giveTheSessionBack];
    [_transcript setString:@""];
    BOOL composer = _composerCapture;
    _composerCapture = NO;
    [self setState:AKDictationStateIdle];
    if (composer) [self composeEvent:@"stopped" text:nil reason:@"cancelled"];
}

#pragma mark - What the recogniser says

- (void)speechReported:(NSString *)transcript isFinal:(BOOL)isFinal error:(NSError *)error session:(NSUInteger)session {
    if (_session != session || _abandoned) return;
    if (transcript.length) [_transcript setString:transcript];
    if (error) {
        // An error is not a final result. In particular, a recogniser can report an error after
        // producing a partial transcript; delivering the cached partial here would violate the
        // final-only rule and could auto-submit an incomplete chat message.
        AKKDLog(@"failure reason=recognizer generation=%lu", (unsigned long)session);
        // The SDK's own description can quote what it heard, so only the fact is recorded.
        [self fail:@"Recognition stopped before it finished, so nothing was typed." reason:@"recognizer"];
        return;
    }
    // A partial result is a progress signal and nothing else. For the Composer it is also the
    // visible draft - which is the one place provisional text may live - and it still cannot be
    // sent, because the Composer disables Send until the result is final.
    if (!isFinal && _composerCapture) {
        if (transcript.length) [self composeEvent:@"draft" text:transcript reason:nil];
        return;
    }
    // A final result is the only thing that ends a session early. Anything else is a
    // partial result, and partial results are not delivered at all.
    if (isFinal) {
        AKKDLog(@"result=final generation=%lu", (unsigned long)session);
        if (_state == AKDictationStateFinalizing) [self finishWithTranscript:transcript];
        return;
    }
    if (!_loggedPartial) {
        _loggedPartial = YES;
        AKKDLog(@"result=partial generation=%lu", (unsigned long)session);
    }
}

// The one place a session ends well. Everything is put back *before* the words go
// anywhere, so the game's audio is already returning while its input is being typed.
- (void)finishWithTranscript:(nullable NSString *)transcript {
    if (_delivered || _abandoned) return;
    _delivered = YES;
    if (transcript.length) [_transcript setString:transcript];
    AKKDLog(@"recognizer.session.end generation=%lu outcome=final", (unsigned long)_session);
    [self giveTheSessionBack];
    [self.speech cancel];
    BOOL composer = _composerCapture;
    _composerCapture = NO;
    [self setState:AKDictationStateIdle];
    if (composer) {
        // The Composer owns the words from here. Nothing is typed into the game, and nothing is
        // sent: Send is a separate, explicit action.
        [self composeEvent:@"final" text:transcript reason:nil];
        return;
    }
    [self deliver];
}

// Handing the session back, once, and saying so when it did not work.
//
// No retries. The review outcome is explicit that a failed put-back leaves an explicit recoverable
// state and a user-visible message rather than an unbounded retry loop, and the retry this replaces
// is the clearest example of why: a retry from a failed put-back could fire after the next dictation
// had begun and take the session away from it, which the user saw as the microphone being broken.
- (void)giveTheSessionBack {
    NSError *error = nil;
    if ([self.audio restore:&error]) {
        AKKDLog(@"audio.restore=ok");
        return;
    }
    AKKDLog(@"audio.restore=failed");
    WKLog("voice", @"audio: the session could not be handed back: %@", error.localizedDescription ?: @"no reason given");
    if (self.problemHandler)
        self.problemHandler(@"The microphone could not be handed back. If the microphone indicator is still on, close WolkaraForever and open it again.");
}

// `reason` is one of the enumerated values in KeyboardDictationEvents.h. The message is for the
// user and is localized where it is composed; nothing is derived from the SDK's own text.
- (void)fail:(NSString *)message reason:(NSString *)reason {
    WKLog("voice", @"dictation: %@", message);
    AKKDLog(@"failure reason=%@ generation=%lu", reason ?: @"unknown", (unsigned long)_session);
    AKKDLog(@"recognizer.session.end generation=%lu outcome=error", (unsigned long)_session);
    [self giveTheSessionBack];
    [self.speech cancel];
    _abandoned = YES;
    _session++;
    BOOL composer = _composerCapture;
    _composerCapture = NO;
    [self setState:AKDictationStateIdle];
    if (composer) [self composeEvent:@"failure" text:nil reason:message];
    void (^problem)(NSString *) = self.problemHandler;
    if (problem) problem(message);
}

// One place the Composer's client is told what happened, so every path that can end a session
// ends it the same way. Lengths only: a dictated line is the speaker's and the log is not.
- (void)composeEvent:(NSString *)event text:(nullable NSString *)text reason:(nullable NSString *)reason {
    void (^handler)(NSString *, NSString *, NSString *) = _composerHandler;
    if (!handler) return;
    WKLog("voice", @"dictation -> the Composer: %@ (%lu character(s))%@", event,
          (unsigned long)(text ?: @"").length,
          reason.length ? [NSString stringWithFormat:@" reason=%@", reason] : @"");
    handler(event, text ?: @"", reason ?: @"");
}

#pragma mark - The words

- (void)deliver {
    NSString *text = [_transcript stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    void (^handler)(NSString *) = _transcriptHandler;
    if (handler) {
        // A test screen is up: the words are its business, not the game's. It is told
        // even when nothing was heard, so it can say so.
        WKLog("voice", @"dictation: heard %lu characters, for the test screen", (unsigned long)text.length);
        handler(text);
        return;
    }
    if (!text.length) { WKLog("voice", @"dictation: stopped, heard nothing"); return; }
    WKLog("voice", @"dictation: heard %lu characters", (unsigned long)text.length);
    if (AKVoiceSettings.shared.trailingSpace) text = [text stringByAppendingString:@" "];
    if ([self typeIntoGame:text]) {
        // Separately, and deliberately: the text goes in first, then Return - and only
        // when it was asked for, which is Handy's auto-submit.
        if (AKVoiceSettings.shared.autoSubmit) [self sendReturn];
    }
}

- (BOOL)typeIntoGame:(NSString *)text {
    UIView *target = AKDictation.gameTextTarget;
    if (!target) {
        AKKDLog(@"failure reason=target");
        WKLog("voice", @"dictation: the game has not registered a text target; nothing typed");
        return NO;
    }
    // Ask before sending, for the same reason the draft editor asks before inserting a
    // dictation placeholder: an object that does not answer the selector aborts the app,
    // and the target is announced by another module that this one cannot check at compile
    // time. It happened - AKKeyboardTextView was announced instead of the view that can
    // reach the guest, and the first spoken sentence killed the app on the device
    // (2026-10-21). A target that cannot take text loses the words; it never kills a
    // running game.
    SEL selector = NSSelectorFromString(@"touchInsertText:");
    if (![target respondsToSelector:selector]) {
        AKKDLog(@"failure reason=target");
        WKLog("voice", @"dictation: the registered text target (%@) does not take text; nothing typed",
              NSStringFromClass(target.class));
        return NO;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [target performSelector:selector withObject:text];
#pragma clang diagnostic pop
    return YES;
}

- (void)sendReturn {
    UIView *target = AKDictation.gameTextTarget;
    if (!target) return;
    SEL selector = NSSelectorFromString(@"touchSpecialKey:characters:");
    if (![target respondsToSelector:selector]) {
        AKKDLog(@"failure reason=target");
        WKLog("voice", @"dictation: the registered text target (%@) does not take keys; nothing sent",
              NSStringFromClass(target.class));
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [target performSelector:selector
                 withObject:@(AKReturnKeyCode)
                 withObject:@"\r"];
#pragma clang diagnostic pop
    WKLog("voice", @"dictation: sent Return");
}

#pragma mark - Telling whoever is watching

- (void)setState:(AKDictationState)state {
    AKDictationState previous = _state;
    _state = state;
    if (previous == state) return;
    WKLog("voice", @"dictation: %@ -> %@", [self nameForState:previous], [self nameForState:state]);
    void (^changed)(BOOL) = _listeningChanged;
    BOOL listening = self.listening;
    BOOL wasListening = previous == AKDictationStateListening || previous == AKDictationStateFinalizing;
    if (changed && listening != wasListening) changed(listening);
    void (^stateHandler)(AKDictationState) = _stateChanged;
    if (stateHandler) stateHandler(state);
}

- (NSString *)nameForState:(AKDictationState)state {
    switch (state) {
    case AKDictationStateIdle: return @"idle";
    case AKDictationStateAuthorizing: return @"authorizing";
    case AKDictationStateListening: return @"listening";
    case AKDictationStateFinalizing: return @"finalizing";
    }
    return @"?";
}

@end
