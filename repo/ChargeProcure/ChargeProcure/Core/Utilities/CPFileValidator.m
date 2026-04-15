#import "CPFileValidator.h"

// Maximum allowed file size: 25 MB
static const NSUInteger kCPFileValidatorMaxSizeBytes = 25 * 1024 * 1024;

// Error domain
static NSString * const kCPFileValidatorErrorDomain = @"com.chargeprocure.filevalidator";

// Error codes
typedef NS_ENUM(NSInteger, CPFileValidatorErrorCode) {
    CPFileValidatorErrorCodeInvalidType  = 1001,
    CPFileValidatorErrorCodeFileTooLarge = 1002,
    CPFileValidatorErrorCodeEmptyData    = 1003,
};

// PDF magic bytes: %PDF  (25 50 44 46)
static const uint8_t kPDFMagic[]  = { 0x25, 0x50, 0x44, 0x46 };
static const NSUInteger kPDFMagicLength = 4;

// JPEG magic bytes: FF D8 FF
static const uint8_t kJPEGMagic[] = { 0xFF, 0xD8, 0xFF };
static const NSUInteger kJPEGMagicLength = 3;

// PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
static const uint8_t kPNGMagic[]  = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
static const NSUInteger kPNGMagicLength = 8;

@implementation CPFileValidator

+ (CPFileType)detectTypeFromData:(NSData *)data {
    if (data.length == 0) {
        return CPFileTypeUnknown;
    }

    const uint8_t *bytes = (const uint8_t *)data.bytes;

    // PDF check — needs at least 4 bytes
    if (data.length >= kPDFMagicLength &&
        memcmp(bytes, kPDFMagic, kPDFMagicLength) == 0) {
        return CPFileTypePDF;
    }

    // PNG check — needs at least 8 bytes
    if (data.length >= kPNGMagicLength &&
        memcmp(bytes, kPNGMagic, kPNGMagicLength) == 0) {
        return CPFileTypePNG;
    }

    // JPEG check — needs at least 3 bytes
    if (data.length >= kJPEGMagicLength &&
        memcmp(bytes, kJPEGMagic, kJPEGMagicLength) == 0) {
        return CPFileTypeJPEG;
    }

    return CPFileTypeUnknown;
}

+ (BOOL)isAllowedType:(CPFileType)type {
    switch (type) {
        case CPFileTypePDF:
        case CPFileTypeJPEG:
        case CPFileTypePNG:
            return YES;
        case CPFileTypeUnknown:
        default:
            return NO;
    }
}

+ (NSString *)mimeTypeForFileType:(CPFileType)type {
    switch (type) {
        case CPFileTypePDF:
            return @"application/pdf";
        case CPFileTypeJPEG:
            return @"image/jpeg";
        case CPFileTypePNG:
            return @"image/png";
        case CPFileTypeUnknown:
        default:
            return @"application/octet-stream";
    }
}

+ (NSString *)extensionForFileType:(CPFileType)type {
    switch (type) {
        case CPFileTypePDF:
            return @"pdf";
        case CPFileTypeJPEG:
            return @"jpg";
        case CPFileTypePNG:
            return @"png";
        case CPFileTypeUnknown:
        default:
            return @"bin";
    }
}

+ (BOOL)validateData:(NSData *)data error:(NSError **)error {
    // Empty data guard
    if (data == nil || data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kCPFileValidatorErrorDomain
                                         code:CPFileValidatorErrorCodeEmptyData
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"File data is empty."
            }];
        }
        return NO;
    }

    // Check magic bytes / type
    CPFileType detectedType = [self detectTypeFromData:data];
    if (![self isAllowedType:detectedType]) {
        if (error) {
            *error = [NSError errorWithDomain:kCPFileValidatorErrorDomain
                                         code:CPFileValidatorErrorCodeInvalidType
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"File type is not allowed. Only PDF, JPEG, and PNG files are accepted."
            }];
        }
        return NO;
    }

    // Check size
    if (data.length > kCPFileValidatorMaxSizeBytes) {
        if (error) {
            NSString *description = [NSString stringWithFormat:
                @"File size (%lu bytes) exceeds the maximum allowed size of 25 MB.",
                (unsigned long)data.length];
            *error = [NSError errorWithDomain:kCPFileValidatorErrorDomain
                                         code:CPFileValidatorErrorCodeFileTooLarge
                                     userInfo:@{
                NSLocalizedDescriptionKey: description
            }];
        }
        return NO;
    }

    return YES;
}

@end
