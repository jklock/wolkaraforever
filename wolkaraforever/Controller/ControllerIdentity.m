#import "ControllerIdentity.h"

#import <GameController/GameController.h>

#import "../Input/InputElement.h"

NSString *AKControllerIdentityForNames(NSString *vendorName, NSString *productCategory) {
    return [NSString stringWithFormat:@"%@.%@",
            AKInputIdentifierSlug(vendorName.length ? vendorName : @"controller"),
            AKInputIdentifierSlug(productCategory.length ? productCategory : @"unknown")];
}

NSString *AKControllerIdentity(GCController *pad) {
    if (!pad) return @"unknown";
    return AKControllerIdentityForNames(pad.vendorName, pad.productCategory);
}
