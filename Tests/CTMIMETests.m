/*
 * MailCore
 *
 * Copyright (C) 2007 - Matt Ronge
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the MailCore project nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#import <XCTest/XCTest.h>

#import "CTCoreMessage.h"
#import "CTMIME.h"
#import <libetpan/libetpan.h>
#import "CTMIMEFactory.h"
#import "CTMIME_MessagePart.h"
#import "CTMIME_MultiPart.h"
#import "CTMIME_SinglePart.h"
#import "CTMIME_TextPart.h"
#import "CTMIME_Enumerator.h"


@interface CTMIMETests : XCTestCase

@end


@implementation CTMIMETests

-(void)setUp {
    self.continueAfterFailure = NO;
}

- (void)testMIMETextPart {
    NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"TestData/kiwi-dev/1167196014.6158_0.theronge.com:2,Sab" ofType:@""];
    CTCoreMessage *msg = [[CTCoreMessage alloc] initWithFileAtPath:filePath];
    CTMIME *mime = [CTMIMEFactory createMIMEWithMIMEStruct:[msg messageStruct]->msg_mime forMessage:[msg messageStruct]];
    XCTAssert([mime isKindOfClass:[CTMIME_MessagePart class]],@"Outmost MIME type should be Message but it's not!");
    XCTAssert([[mime content] isKindOfClass:[CTMIME_MultiPart class]],@"Incorrect MIME structure found!");
    NSArray *multiPartContent = [[mime content] content];
    XCTAssert([multiPartContent count] == 2, @"Incorrect MIME structure found!");
    XCTAssert([[multiPartContent objectAtIndex:0] isKindOfClass:[CTMIME_TextPart class]], @"Incorrect MIME structure found!");
    XCTAssert([[multiPartContent objectAtIndex:1] isKindOfClass:[CTMIME_TextPart class]], @"Incorrect MIME structure found!");
}

- (void)testSmallMIME {
    CTMIME_TextPart *text1 = [CTMIME_TextPart mimeTextPartWithString:@"Hello there!"];
    CTMIME_TextPart *text2 = [CTMIME_TextPart mimeTextPartWithString:@"This is part 2"];
    CTMIME_MultiPart *multi = [CTMIME_MultiPart mimeMultiPart];
    [multi addMIMEPart:text1];
    [multi addMIMEPart:text2];
    CTMIME_MessagePart *messagePart = [CTMIME_MessagePart mimeMessagePartWithContent:multi];
    NSData * data = [messagePart renderData];
    XCTAssertNotNil(data);
    [data writeToFile:@"/tmp/mailcore_test_output" atomically:NO];
    mmap_string_unref((char *)data.bytes);

    CTCoreMessage *msg = [[CTCoreMessage alloc] initWithFileAtPath:@"/tmp/mailcore_test_output"];
    CTMIME *mime = [CTMIMEFactory createMIMEWithMIMEStruct:[msg messageStruct]->msg_mime forMessage:[msg messageStruct]];
    XCTAssert([mime isKindOfClass:[CTMIME_MessagePart class]],@"Outmost MIME type should be Message but it's not!");
    XCTAssert([[mime content] isKindOfClass:[CTMIME_MultiPart class]],@"Incorrect MIME structure found!");
    NSArray *multiPartContent = [[mime content] content];
    XCTAssert([multiPartContent count] == 2, @"Incorrect MIME structure found!");
    XCTAssert([[multiPartContent objectAtIndex:0] isKindOfClass:[CTMIME_TextPart class]], @"Incorrect MIME structure found!");
    XCTAssert([[multiPartContent objectAtIndex:1] isKindOfClass:[CTMIME_TextPart class]], @"Incorrect MIME structure found!");
}

- (void)testBruteForce {
    // run it on a bunch of the files in the test data directory and see if we can get it to crash
    NSString *directory = [[NSBundle bundleForClass:[self class]] resourcePath];
    NSString *filesDirectory = [directory stringByAppendingPathComponent:@"TestData/kiwi-dev/"];

    NSError *error;
    NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:filesDirectory error:&error];

    NSRange notFound = NSMakeRange(NSNotFound, 0);
    for (NSString *file in directoryContents) {
        if (!NSEqualRanges([file rangeOfString:@".svn"],notFound))
            continue;

        NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:[NSString stringWithFormat:@"TestData/kiwi-dev/%@",file] ofType:@""];
        CTCoreMessage *msg = [[CTCoreMessage alloc] initWithFileAtPath:filePath];
        NSLog(@"%@", [msg subject]);
        [msg fetchBodyStructure];
        NSString *stuff = [msg body];
        [stuff length]; //Get the warning to shutup about stuff not being used
    }
}

- (void)testImageJPEGAttachment {
    NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"TestData/mime-tests/imagetest" ofType:@""];
    CTCoreMessage *msg = [[CTCoreMessage alloc] initWithFileAtPath:filePath];

    CTMIME *mime = [CTMIMEFactory createMIMEWithMIMEStruct:[msg messageStruct]->msg_mime forMessage:[msg messageStruct]];
    XCTAssert([mime isKindOfClass:[CTMIME_MessagePart class]],@"Outmost MIME type should be Message but it's not!");
    XCTAssert([[mime content] isKindOfClass:[CTMIME_MultiPart class]],@"Incorrect MIME structure found!");
    NSArray *multiPartContent = [[mime content] content];
    XCTAssert([multiPartContent count] == 3, @"Incorrect MIME structure found!");
    XCTAssert([[multiPartContent objectAtIndex:0] isKindOfClass:[CTMIME_TextPart class]], @"Incorrect MIME structure found!");
    XCTAssert([[multiPartContent objectAtIndex:1] isKindOfClass:[CTMIME_SinglePart class]], @"Incorrect MIME structure found!");
    CTMIME_SinglePart *img = [multiPartContent objectAtIndex:1];
    // For JPEG's we are ignoring the Content-Disposition: inline; not sure if we should be doing this?
    XCTAssert(img.attached == TRUE, @"");
    XCTAssertEqualObjects(img.filename, @"mytestimage.jpg", @"Filename of inline image not correct");
}

- (void)testImagePNGAttachment {
    NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"TestData/mime-tests/png_attachment" ofType:@""];
    CTCoreMessage *msg = [[CTCoreMessage alloc] initWithFileAtPath:filePath];

    CTMIME *mime = [CTMIMEFactory createMIMEWithMIMEStruct:
                    [msg messageStruct]->msg_mime forMessage:[msg messageStruct]];
    XCTAssert([mime isKindOfClass:[CTMIME_MessagePart class]],
              @"Outmost MIME type should be Message but it's not!");
    XCTAssert([[mime content] isKindOfClass:[CTMIME_MultiPart class]],
              @"Incorrect MIME structure found!");
    NSArray *multiPartContent = [[mime content] content];
    XCTAssert([multiPartContent count] == 2,
              @"Incorrect MIME structure found!");
    XCTAssert([[multiPartContent objectAtIndex:0] isKindOfClass:[CTMIME_TextPart class]],
              @"Incorrect MIME structure found!");
    XCTAssert([[multiPartContent objectAtIndex:1] isKindOfClass:[CTMIME_SinglePart class]],
              @"Incorrect MIME structure found!");
    CTMIME_SinglePart *img = [multiPartContent objectAtIndex:1];
    XCTAssert(img.attached == TRUE, @"Image is should be attached");
    XCTAssertEqualObjects(img.filename, @"Picture 1.png", @"Filename of inline image not correct");
}

- (void)testEnumerator {
    NSString *filePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"TestData/mime-tests/png_attachment" ofType:@""];
    CTCoreMessage *msg = [[CTCoreMessage alloc] initWithFileAtPath:filePath];

    CTMIME *mime = [CTMIMEFactory createMIMEWithMIMEStruct:
                    [msg messageStruct]->msg_mime forMessage:[msg messageStruct]];
    CTMIME_Enumerator *enumerator = [mime mimeEnumerator];
    NSArray *allObjects = [enumerator allObjects];
    XCTAssert([[allObjects objectAtIndex:0] isKindOfClass:[CTMIME_MessagePart class]],
              @"Incorrect MIME structure found!");
    XCTAssertEqualObjects([[allObjects objectAtIndex:0] contentType], @"message/rfc822",
                          @"found incorrect contentType");
    XCTAssert([[allObjects objectAtIndex:1] isKindOfClass:[CTMIME_MultiPart class]],
              @"Incorrect MIME structure found!");
    XCTAssertEqualObjects([[allObjects objectAtIndex:1] contentType], @"multipart/mixed",
                          @"found incorrect contentType");
    XCTAssert([[allObjects objectAtIndex:2] isKindOfClass:[CTMIME_TextPart class]],
              @"Incorrect MIME structure found!");
    XCTAssertEqualObjects([[allObjects objectAtIndex:2] contentType], @"text/plain",
                          @"found incorrect contentType");
    XCTAssert([[allObjects objectAtIndex:3] isKindOfClass:[CTMIME_SinglePart class]],
              @"Incorrect MIME structure found!");
    XCTAssertEqualObjects([[allObjects objectAtIndex:3] contentType], @"image/png",
                          @"found incorrect contentType");
    XCTAssert([enumerator nextObject] == nil, @"Should have been nil");
    NSArray *fullAllObjects = allObjects;

    enumerator = [[mime content] mimeEnumerator];
    allObjects = [enumerator allObjects];
    XCTAssert([[allObjects objectAtIndex:0] isKindOfClass:[CTMIME_MultiPart class]],
              @"Incorrect MIME structure found!");
    XCTAssert([[allObjects objectAtIndex:1] isKindOfClass:[CTMIME_TextPart class]],
              @"Incorrect MIME structure found!");
    XCTAssert([[allObjects objectAtIndex:2] isKindOfClass:[CTMIME_SinglePart class]],
              @"Incorrect MIME structure found!");
    XCTAssert([enumerator nextObject] == nil, @"Should have been nil");

    enumerator = [[[[mime content] content] objectAtIndex:0] mimeEnumerator];
    allObjects = [enumerator allObjects];
    XCTAssert([[allObjects objectAtIndex:0] isKindOfClass:[CTMIME_TextPart class]],
              @"Incorrect MIME structure found!");
    XCTAssert([enumerator nextObject] == nil, @"Should have been nil");

    enumerator = [mime mimeEnumerator];
    NSMutableArray *objects = [NSMutableArray array];
    CTMIME *obj;
    while ((obj = [enumerator nextObject])) {
        [objects addObject:obj];
    }
    XCTAssertEqualObjects(objects, fullAllObjects, @"nextObject isn't iterating over the same objects ast allObjects");
}


- (void)testAttachedEML {
    NSString * filePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"TestData/mime-tests/attached-eml" ofType:@""];
    CTCoreMessage * msg = [[CTCoreMessage alloc] initWithFileAtPath:filePath];
    struct mailmessage * messageStruct = msg.messageStruct;
    CTMIME * mime = [CTMIMEFactory createMIMEWithMIMEStruct:messageStruct->msg_mime forMessage:messageStruct];
    XCTAssert([mime isKindOfClass:[CTMIME_MessagePart class]]);
    XCTAssert([mime.content isKindOfClass:[CTMIME_MultiPart class]]);
    CTMIME_MultiPart * multiPart = mime.content;
    NSArray * multiPartContent = multiPart.content;
    XCTAssertEqual(multiPartContent.count, 2);
    XCTAssert([multiPartContent[0] isKindOfClass:[CTMIME_MultiPart class]]);
    XCTAssert([multiPartContent[1] isKindOfClass:[CTMIME_MessagePart class]]);
    NSArray * bodyParts = ((CTMIME_MultiPart *)multiPartContent[0]).content;
    XCTAssertEqual(bodyParts.count, 2);
    XCTAssert([bodyParts[0] isKindOfClass:[CTMIME_TextPart class]]);
    XCTAssert([bodyParts[1] isKindOfClass:[CTMIME_TextPart class]]);
    CTMIME * emlPart = ((CTMIME_MessagePart *)multiPartContent[1]).content;
    XCTAssert([emlPart isKindOfClass:[CTMIME_MultiPart class]]);
    NSArray * emlParts = emlPart.content;
    XCTAssertEqual(emlParts.count, 2);
    XCTAssert([emlParts[0] isKindOfClass:[CTMIME_MultiPart class]]);
    XCTAssert([emlParts[1] isKindOfClass:[CTMIME_SinglePart class]]);
    NSArray * emlBodyParts = ((CTMIME_MultiPart *)multiPartContent[0]).content;
    XCTAssertEqual(emlBodyParts.count, 2);
    XCTAssert([emlBodyParts[0] isKindOfClass:[CTMIME_TextPart class]]);
    XCTAssert([emlBodyParts[1] isKindOfClass:[CTMIME_TextPart class]]);
    CTMIME_SinglePart * imgPart = emlParts[1];
    XCTAssertEqualObjects(imgPart.filename, @"Katakana_u_and_small_i_serif_1.svg");

    __unused NSString * body = msg.body;
    __unused NSString * html = msg.htmlBody;
    NSString * expectedBody = @"This is the outer test email.\r\n\r\nIt has Test inner email.eml as an attachment.\r\n\r\nIt tests like nothing has tested before.\r\n\r\n";
    NSString * expectedHtml = @"<html>\r\n<head>\r\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=us-ascii\">\r\n</head>\r\n<body style=\"word-wrap: break-word; -webkit-nbsp-mode: space; -webkit-line-break: after-white-space; color: rgb(0, 0, 0); font-size: 14px; font-family: Calibri, sans-serif;\">\r\n<div>This is the outer test email.</div>\r\n<div><br>\r\n</div>\r\n<div>It has Test inner email.eml as an attachment.</div>\r\n<div><br>\r\n</div>\r\n<div>It tests like nothing has tested before.</div>\r\n<div><br>\r\n</div>\r\n</body>\r\n</html>\r\n";
    XCTAssertEqualObjects(body, expectedBody);
    XCTAssertEqualObjects(html, expectedHtml);
}


@end
