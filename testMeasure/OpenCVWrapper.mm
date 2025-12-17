//
//  OpenCVWrapper.mm
//  testMeasure
//
//  OpenCV wrapper implementation
//

#import "OpenCVWrapper.h"
#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>

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

