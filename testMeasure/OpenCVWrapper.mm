//
//  OpenCVWrapper.mm
//  testMeasure
//
//  OpenCV wrapper implementation
//

#import "OpenCVWrapper.h"

#ifdef __cplusplus
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
// Only import required OpenCV modules to avoid stitching conflicts
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
#import <opencv2/imgcodecs/ios.h>
#pragma clang diagnostic pop
#endif

@implementation OpenCVWrapper

+ (UIImage *)convertToGrayscale:(UIImage *)image {
    // Convert UIImage to cv::Mat
    cv::Mat colorMat;
    UIImageToMat(image, colorMat);
    
    // Convert to grayscale
    cv::Mat grayMat;
    cv::cvtColor(colorMat, grayMat, cv::COLOR_BGR2GRAY);
    
    // Convert back to UIImage
    UIImage *grayImage = MatToUIImage(grayMat);
    
    return grayImage;
}

+ (NSString *)openCVVersion {
    return [NSString stringWithFormat:@"%s", CV_VERSION];
}

@end

