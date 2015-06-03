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

#import "CTMIME_SinglePart.h"

#import <libetpan/libetpan.h>
#import "MailCoreTypes.h"
#import "MailCoreUtilities.h"


@interface CTMIME_SinglePart ()
@end

@implementation CTMIME_SinglePart
@synthesize attached=mAttached;
@synthesize filename=mFilename;
@synthesize contentId=mContentId;

+ (id)mimeSinglePartWithData:(NSData *)data {
    return [[[CTMIME_SinglePart alloc] initWithData:data] autorelease];
}

- (id)initWithMIMEStruct:(struct mailmime *)mime 
        forMessage:(struct mailmessage *)message {
    self = [super initWithMIMEStruct:mime forMessage:message];
    if (self) {
        mMimeFields = mailmime_single_fields_new(mMime->mm_mime_fields, mMime->mm_content_type);
        if (mMimeFields != NULL) {
            if (mMimeFields->fld_id != NULL) {
                self.contentId = [NSString stringWithCString:mMimeFields->fld_id encoding:NSUTF8StringEncoding];
            }
            
            struct mailmime_disposition *disp = mMimeFields->fld_disposition;
            if (disp != NULL) {
                if (disp->dsp_type != NULL) {
                    self.attached = (disp->dsp_type->dsp_type ==
                                        MAILMIME_DISPOSITION_TYPE_ATTACHMENT);

                    if (self.attached)
                    {
                        // MWA workaround for bug where specific emails look like this:
                        // Content-Type: application/vnd.ms-excel; name="=?UTF-8?B?TVhBVC0zMTFfcGFja2xpc3QxMTA0MDAueGxz?="
                        // Content-Disposition: attachment
                        // - usually they look like -
                        // Content-Type: image/jpeg; name="photo.JPG"
                        // Content-Disposition: attachment; filename="photo.JPG"
                        if (mMimeFields->fld_disposition_filename == NULL && mMimeFields->fld_content_name != NULL)
                            mMimeFields->fld_disposition_filename = mMimeFields->fld_content_name;
                    }
                }
            }

            if ((mMimeFields->fld_disposition_filename != NULL) || (mMimeFields->fld_content_name != NULL)) {


                self.filename = (mMimeFields->fld_disposition_filename != NULL) ?
                            [NSString stringWithCString:mMimeFields->fld_disposition_filename encoding:NSUTF8StringEncoding]
                :
                            [NSString stringWithCString:mMimeFields->fld_content_name encoding:NSUTF8StringEncoding];

                NSString* lowercaseName = [self.filename lowercaseString];
                if([lowercaseName hasSuffix:@".xls"] ||
                    [lowercaseName hasSuffix:@".xlsx"] ||
                    [lowercaseName hasSuffix:@".key.zip"] ||
                    [lowercaseName hasSuffix:@".numbers.zip"] ||
                    [lowercaseName hasSuffix:@".pages.zip"] ||
                    [lowercaseName hasSuffix:@".pdf"] ||
                    [lowercaseName hasSuffix:@".ppt"] ||
                    [lowercaseName hasSuffix:@".doc"] ||
                    [lowercaseName hasSuffix:@".docx"] ||
                    [lowercaseName hasSuffix:@".rtf"] ||
                    [lowercaseName hasSuffix:@".rtfd.zip"] ||
                    [lowercaseName hasSuffix:@".key"] ||
                    [lowercaseName hasSuffix:@".numbers"] ||
                    [lowercaseName hasSuffix:@".pages"] ||
                    [lowercaseName hasSuffix:@".png"] ||
                    [lowercaseName hasSuffix:@".gif"] ||
                    [lowercaseName hasSuffix:@".png"] ||
                    [lowercaseName hasSuffix:@".jpg"] ||
                    [lowercaseName hasSuffix:@".jpeg"] ||
                    [lowercaseName hasSuffix:@".tiff"]) { // hack by gabor, improved by waseem, based on http://developer.apple.com/iphone/library/qa/qa2008/qa1630.html
                    self.attached = YES;
                }
            }

        }
    }
    return self;
}

- (struct mailmime *)buildMIMEStruct {
    struct mailmime_fields *mime_fields;
    struct mailmime *mime_sub;
    struct mailmime_content *content;
    int r;

    if (mContentId) {
        
        char *fileNameData = NULL;
        if (mFilename != nil) {
            char *fileNameChar = (char *)[mFilename cStringUsingEncoding:NSUTF8StringEncoding];
            fileNameData = malloc(strlen(fileNameChar) + 1);
            strcpy(fileNameData, fileNameChar);
        }
        
        struct mailmime_mechanism * encoding = mailmime_mechanism_new(MAILMIME_MECHANISM_BASE64, NULL);
        struct mailmime_disposition* disposition = mailmime_disposition_new_with_data(MAILMIME_DISPOSITION_TYPE_INLINE, fileNameData, NULL, NULL, NULL, -1);

        char *charData = (char *)[mContentId cStringUsingEncoding:NSUTF8StringEncoding];
        char *dupeData = malloc(strlen(charData) + 1);
        strcpy(dupeData, charData);
        mime_fields = mailmime_fields_new_with_data(encoding, dupeData, NULL, disposition, NULL);
//        mime_fields = mailmime_fields_new_with_data(MAILMIME_DISPOSITION_TYPE_INLINE, dupeData, NULL
//                                                    , NULL, NULL);
//        
//        struct mailmime_fields * encodingFields = mailmime_fields_new_encoding(MAILMIME_MECHANISM_BASE64);
//        r = mailmime_fields_add(mime_fields, (struct mailmime_field *)encodingFields->fld_list->first);
    }
    else if (mFilename) {
        char *charData = (char *)[mFilename cStringUsingEncoding:NSUTF8StringEncoding];
        char *dupeData = malloc(strlen(charData) + 1);
        strcpy(dupeData, charData);

        // RFC 2046 5.2.1. RFC822 Subtype
        // No encoding other than "7bit", "8bit", or "binary" is permitted for
        // the body of a "message/rfc822" entity.
        int encoding_type = ([self.contentType isEqualToString:@"message/rfc822"] ?
                             MAILMIME_MECHANISM_8BIT :
                             MAILMIME_MECHANISM_BASE64);

        mime_fields = mailmime_fields_new_filename( MAILMIME_DISPOSITION_TYPE_ATTACHMENT, 
                                                    dupeData,
                                                    encoding_type );
    } else {
        mime_fields = mailmime_fields_new_encoding(MAILMIME_MECHANISM_BASE64);
    }
    content = mailmime_content_new_with_str([self.contentType cStringUsingEncoding:NSUTF8StringEncoding]);
    mime_sub = mailmime_new_empty(content, mime_fields);

    // mailmime_new_empty checks ct_subtype for rfc822, and will set mm_type = MAILMIME_MESSAGE
    // in that case.  This is wrong for us, because we are attaching the message as an attachment
    // (implicit in the fact that this instance is CTMIME_SinglePart and not CTMIME_MessagePart).
    //
    // In particular, we can't call mailmime_set_body_text if mm_type == MAILMIME_MESSAGE, because
    // that call sets mime_sub->mm_data.mm_single to hold the attachment body, and that's only
    // valid if mm_type == MAILMIME_SINGLE.  mm_data is a union, so we crashed when later accessing
    // that same data through mime_sub->mm_data.mm_message and erroneously re-interpreting it.
    //
    // Change it to mm_type = MAILMIME_SINGLE before proceeding.
    if (strcasecmp(content->ct_subtype, "rfc822") == 0) {
        mime_sub->mm_type = MAILMIME_SINGLE;
    }

    // Add Data
    r = mailmime_set_body_text(mime_sub, (char *)[self.data bytes], [self.data length]);
    return mime_sub;
}

- (size_t)size {
    if (mMime) {
        return mMime->mm_length;
    }
    return 0;
}

- (struct mailmime_single_fields *)mimeFields {
    return mMimeFields;
}

- (void)dealloc {
    mailmime_single_fields_free(mMimeFields);
    [mFilename release];
    [mContentId release];
    [super dealloc];
}
@end
