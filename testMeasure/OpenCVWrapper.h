//
//  OpenCVWrapper.h
//  testMeasure
//
//  OpenCV wrapper for Swift
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

// Convert RGB image to grayscale using OpenCV
+ (UIImage *)convertToGrayscale:(UIImage *)image;

// Get OpenCV version
+ (NSString *)openCVVersion;

@end

NS_ASSUME_NONNULL_END

