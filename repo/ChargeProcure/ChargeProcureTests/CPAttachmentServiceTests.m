#import <XCTest/XCTest.h>
#import "CPAttachmentService.h"
#import "CPTestCoreDataStack.h"
#import <CoreData/CoreData.h>

@interface CPAttachmentServiceTests : XCTestCase
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@end

@implementation CPAttachmentServiceTests

- (void)setUp {
    [super setUp];
    [[CPTestCoreDataStack sharedStack] resetAll];
    self.ctx = [CPTestCoreDataStack sharedStack].mainContext;
}

- (void)tearDown {
    [[CPTestCoreDataStack sharedStack] resetAll];
    [super tearDown];
}

// ---------------------------------------------------------------------------
// Helpers to build minimal valid file data with correct magic bytes
// ---------------------------------------------------------------------------

- (NSData *)makePDFData {
    // Minimal %PDF- header followed by padding to make a realistic small file
    NSMutableData *data = [NSMutableData data];
    uint8_t header[] = {0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34}; // %PDF-1.4
    [data appendBytes:header length:sizeof(header)];
    // Pad to 100 bytes
    NSData *padding = [NSMutableData dataWithLength:92];
    [data appendData:padding];
    return [data copy];
}

- (NSData *)makeJPEGData {
    NSMutableData *data = [NSMutableData data];
    uint8_t header[] = {0xFF, 0xD8, 0xFF, 0xE0}; // JPEG SOI + APP0 marker
    [data appendBytes:header length:sizeof(header)];
    NSData *padding = [NSMutableData dataWithLength:96];
    [data appendData:padding];
    return [data copy];
}

- (NSData *)makePNGData {
    NSMutableData *data = [NSMutableData data];
    uint8_t header[] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}; // PNG signature
    [data appendBytes:header length:sizeof(header)];
    NSData *padding = [NSMutableData dataWithLength:92];
    [data appendData:padding];
    return [data copy];
}

- (NSData *)makeTextData {
    return [@"This is plain text, not a valid attachment type." dataUsingEncoding:NSUTF8StringEncoding];
}

// ---------------------------------------------------------------------------
// 1. testPDFMagicHeaderAccepted — %PDF data accepted
// ---------------------------------------------------------------------------
- (void)testPDFMagicHeaderAccepted {
    NSData *pdfData = [self makePDFData];
    CPAttachmentFileType type = [[CPAttachmentService sharedService] detectFileTypeFromData:pdfData];
    XCTAssertEqual(type, CPAttachmentFileTypePDF,
                   @"Data starting with %%PDF should be detected as PDF");
}

// ---------------------------------------------------------------------------
// 2. testJPEGMagicHeaderAccepted — FFD8FF data accepted
// ---------------------------------------------------------------------------
- (void)testJPEGMagicHeaderAccepted {
    NSData *jpegData = [self makeJPEGData];
    CPAttachmentFileType type = [[CPAttachmentService sharedService] detectFileTypeFromData:jpegData];
    XCTAssertEqual(type, CPAttachmentFileTypeJPEG,
                   @"Data starting with FFD8FF should be detected as JPEG");
}

// ---------------------------------------------------------------------------
// 3. testPNGMagicHeaderAccepted — 89504E47 data accepted
// ---------------------------------------------------------------------------
- (void)testPNGMagicHeaderAccepted {
    NSData *pngData = [self makePNGData];
    CPAttachmentFileType type = [[CPAttachmentService sharedService] detectFileTypeFromData:pngData];
    XCTAssertEqual(type, CPAttachmentFileTypePNG,
                   @"Data starting with 89504E47 should be detected as PNG");
}

// ---------------------------------------------------------------------------
// 4. testInvalidTypeRejected — text data returns CPAttachmentErrorInvalidType
// ---------------------------------------------------------------------------
- (void)testInvalidTypeRejected {
    NSData *textData = [self makeTextData];

    // First confirm detection identifies it as unknown
    CPAttachmentFileType type = [[CPAttachmentService sharedService] detectFileTypeFromData:textData];
    XCTAssertEqual(type, CPAttachmentFileTypeUnknown,
                   @"Plain text should be detected as unknown file type");

    // Now attempt to save — should return error CPAttachmentErrorInvalidType
    NSError *err = nil;
    NSString *uuid = [[CPAttachmentService sharedService]
                      saveAttachmentData:textData
                      filename:@"test.txt"
                      ownerID:@"owner-001"
                      ownerType:@"Invoice"
                      error:&err];

    XCTAssertNil(uuid, @"Saving text data should fail");
    XCTAssertNotNil(err, @"Error should be returned for invalid file type");
    XCTAssertEqual(err.code, CPAttachmentErrorInvalidType,
                   @"Error code should be CPAttachmentErrorInvalidType");
}

// ---------------------------------------------------------------------------
// 5. testFileTooLargeRejected — saveAttachmentData with >25MB returns CPAttachmentErrorFileTooLarge
// ---------------------------------------------------------------------------
- (void)testFileTooLargeRejected {
    XCTAssertEqual(CPAttachmentMaxSizeBytes, 25 * 1024 * 1024,
                   @"CPAttachmentMaxSizeBytes limit should be exactly 25MB");

    // Allocate 25MB + 1 byte. The service must reject this before writing to disk.
    NSUInteger oversizeBytes = (NSUInteger)CPAttachmentMaxSizeBytes + 1;
    NSMutableData *bigData = [NSMutableData dataWithLength:oversizeBytes];
    // Prepend a valid PDF magic header so the rejection is purely size-based, not type-based.
    uint8_t pdfHeader[] = {0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34};
    [bigData replaceBytesInRange:NSMakeRange(0, sizeof(pdfHeader))
                       withBytes:pdfHeader];

    NSError *err = nil;
    NSString *uuid = [[CPAttachmentService sharedService]
                      saveAttachmentData:bigData
                      filename:@"huge.pdf"
                      ownerID:@"owner-big"
                      ownerType:@"Invoice"
                      error:&err];

    XCTAssertNil(uuid, @"Saving >25MB data should return nil");
    XCTAssertNotNil(err, @"An error should be returned for oversized attachment");
    XCTAssertEqualObjects(err.domain, CPAttachmentErrorDomain,
                          @"Error domain should be CPAttachmentErrorDomain");
    XCTAssertEqual(err.code, CPAttachmentErrorFileTooLarge,
                   @"Error code should be CPAttachmentErrorFileTooLarge (4001)");
}

// ---------------------------------------------------------------------------
// 6. testAttachmentSavedAndLoadable — save then load returns same data
// ---------------------------------------------------------------------------
- (void)testAttachmentSavedAndLoadable {
    NSData *pdfData = [self makePDFData];

    NSError *saveErr = nil;
    NSString *attachmentUUID = [[CPAttachmentService sharedService]
                                saveAttachmentData:pdfData
                                filename:@"test_document.pdf"
                                ownerID:@"invoice-uuid-001"
                                ownerType:@"Invoice"
                                error:&saveErr];

    XCTAssertNil(saveErr, @"PDF attachment save should succeed, got: %@", saveErr);
    XCTAssertNotNil(attachmentUUID, @"Saved attachment should return a UUID");

    if (attachmentUUID) {
        NSError *loadErr = nil;
        NSData *loadedData = [[CPAttachmentService sharedService]
                              loadAttachmentWithUUID:attachmentUUID
                              error:&loadErr];

        XCTAssertNil(loadErr, @"Load should succeed, got: %@", loadErr);
        XCTAssertNotNil(loadedData, @"Loaded data should not be nil");
        XCTAssertEqualObjects(loadedData, pdfData,
                              @"Loaded data should be identical to the saved data");

        // Cleanup: delete the attachment
        NSError *deleteErr = nil;
        [[CPAttachmentService sharedService] deleteAttachment:attachmentUUID error:&deleteErr];
    }
}

// ---------------------------------------------------------------------------
// 7. testAttachmentDeleted — delete removes file and Core Data record
// ---------------------------------------------------------------------------
- (void)testAttachmentDeleted {
    // First save an attachment
    NSData *jpegData = [self makeJPEGData];

    NSError *saveErr = nil;
    NSString *attachmentUUID = [[CPAttachmentService sharedService]
                                saveAttachmentData:jpegData
                                filename:@"photo.jpg"
                                ownerID:@"receipt-uuid-001"
                                ownerType:@"Receipt"
                                error:&saveErr];

    XCTAssertNil(saveErr, @"JPEG attachment save should succeed");
    XCTAssertNotNil(attachmentUUID, @"Attachment UUID should be returned on save");

    if (attachmentUUID) {
        // Now delete it
        NSError *deleteErr = nil;
        BOOL deleted = [[CPAttachmentService sharedService]
                        deleteAttachment:attachmentUUID
                        error:&deleteErr];

        XCTAssertTrue(deleted, @"Attachment delete should succeed");
        XCTAssertNil(deleteErr, @"No error expected on delete");

        // Attempting to load after delete should fail
        NSError *loadErr = nil;
        NSData *afterDeleteData = [[CPAttachmentService sharedService]
                                   loadAttachmentWithUUID:attachmentUUID
                                   error:&loadErr];

        XCTAssertNil(afterDeleteData, @"Loading deleted attachment should return nil");
        XCTAssertNotNil(loadErr, @"Error should be returned when loading a deleted attachment");
    }
}

@end
