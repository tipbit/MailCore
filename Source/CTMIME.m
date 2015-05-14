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

#import "CTMIME.h"

#import <libetpan/libetpan.h>
#import "CTMIME_Enumerator.h"
#import "MailCoreTypes.h"
#import "MailCoreUtilities.h"

static inline struct imap_session_state_data *
get_session_data(mailmessage * msg)
{
    return msg->msg_session->sess_data;
}

static inline mailimap * get_imap_session(mailmessage * msg)
{
    return get_session_data(msg)->imap_session;
}

static void download_progress_callback(size_t current, size_t maximum, void * context) {
    CTProgressBlock block = context;
    block(current, maximum);
}

@implementation CTMIME
@synthesize contentType=mContentType;
@synthesize data=mData;
@synthesize fetched=mFetched;
@synthesize lastError;

- (id)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        self.data = data;
        self.fetched = YES;
    }
    return self;
}

- (id)initWithMIMEStruct:(struct mailmime *)mime
        forMessage:(struct mailmessage *)message {
    self = [super init];
    if (self) {
        self.data = nil;
        mMime = mime;
        mMessage = message;
        self.fetched = NO;

        // We couldn't find a content-type, set it to something generic
        NSString *mainType = @"application";
        NSString *subType = @"octet-stream";
        if (mime != NULL && mime->mm_content_type != NULL) {
            struct mailmime_content *content = mime->mm_content_type;
            if (content->ct_type != NULL) {
                subType = [NSString stringWithCString:content->ct_subtype
                            encoding:NSUTF8StringEncoding];
                subType = [subType lowercaseString];
                struct mailmime_type *type = content->ct_type;
                if (type->tp_type == MAILMIME_TYPE_DISCRETE_TYPE &&
                    type->tp_data.tp_discrete_type != NULL) {
                    switch (type->tp_data.tp_discrete_type->dt_type) {
                        case MAILMIME_DISCRETE_TYPE_TEXT:
                            mainType = @"text";
                        break;
                        case MAILMIME_DISCRETE_TYPE_IMAGE:
                            mainType = @"image";
                        break;
                        case MAILMIME_DISCRETE_TYPE_AUDIO:
                            mainType = @"audio";
                        break;
                        case MAILMIME_DISCRETE_TYPE_VIDEO:
                            mainType = @"video";
                        break;
                        case MAILMIME_DISCRETE_TYPE_APPLICATION:
                            mainType = @"application";
                        break;
                    }
                }
                else if (type->tp_type == MAILMIME_TYPE_COMPOSITE_TYPE &&
                            type->tp_data.tp_composite_type != NULL) {
                    switch (type->tp_data.tp_discrete_type->dt_type) {
                        case MAILMIME_COMPOSITE_TYPE_MESSAGE:
                            mainType = @"message";
                        break;
                        case MAILMIME_COMPOSITE_TYPE_MULTIPART:
                            mainType = @"multipart";
                        break;
                    }
                }
            }
        }
        mContentType = [[NSString alloc] initWithFormat:@"%@/%@", mainType, subType];
    }
    return self;
}

- (id)content {
    return nil;
}

- (NSString *)contentType {
    return mContentType;
}

- (BOOL)fetchPartWithProgress:(CTProgressBlock)block {
    if (self.fetched == NO) {
        struct mailmime_single_fields *mimeFields = NULL;

        int encoding = MAILMIME_MECHANISM_8BIT;
        mimeFields = mailmime_single_fields_new(mMime->mm_mime_fields, mMime->mm_content_type);
        if (mimeFields != NULL && mimeFields->fld_encoding != NULL)
            encoding = mimeFields->fld_encoding->enc_type;

        char *fetchedData = NULL;
        size_t fetchedDataLen;
        int r;

        if (mMessage->msg_session != NULL) {
            mailimap_set_progress_callback(get_imap_session(mMessage), &download_progress_callback, NULL, block);
        }
        r = mailmessage_fetch_section(mMessage, mMime, &fetchedData, &fetchedDataLen);
        if (mMessage->msg_session != NULL) {
            mailimap_set_progress_callback(get_imap_session(mMessage), NULL, NULL, NULL);
        }
        if (r != MAIL_NO_ERROR) {
            if (fetchedData) {
                mailmessage_fetch_result_free(mMessage, fetchedData);
            }
            self.lastError = MailCoreCreateErrorFromIMAPCode(r);
            return NO;
        }


        size_t current_index = 0;
        char * result;
        size_t result_len;
        r = mailmime_part_parse(fetchedData, fetchedDataLen, &current_index,
                                encoding, &result, &result_len);
        if (r != MAILIMF_NO_ERROR) {
            mailmime_decoded_part_free(result);
            self.lastError = MailCoreCreateError(r, @"Error parsing the message");
            return NO;
        }
        NSData *data = [NSData dataWithBytes:result length:result_len];
        mailmessage_fetch_result_free(mMessage, fetchedData);
        mailmime_decoded_part_free(result);
        mailmime_single_fields_free(mimeFields);
        self.data = data;
        self.fetched = YES;
    }
    return YES;
}

- (BOOL)fetchPart {
    return [self fetchPartWithProgress:^(size_t curr, size_t max){}];
}

- (struct mailmime *)buildMIMEStruct {
    return NULL;
}


-(NSData *)renderData {
    struct mailmime * mime = [self buildMIMEStruct];
    if (mime == NULL) {
        return nil;
    }

    MMAPString * str = mmap_string_new("");
    int col = 0;
    mailmime_write_mem(str, &col, mime);
    int err = mmap_string_ref(str);

    mime->mm_data.mm_message.mm_fields = NULL;
    mailmime_free(mime);

    if (err == 0) {
        return [NSData dataWithBytesNoCopy:str->str length:str->len freeWhenDone:NO];
    }
    else {
        self.lastError = [NSError errorWithDomain:MailCoreErrorDomain code:MAIL_ERROR_MEMORY userInfo:nil];
        return nil;
    }
}

- (CTMIME_Enumerator *)mimeEnumerator {
    CTMIME_Enumerator *enumerator;
    enumerator = [[CTMIME_Enumerator alloc] initWithMIME:self];
    return [enumerator autorelease];
}

- (void)dealloc {
    [mContentType release];
    [mData release];
    self.lastError = nil;
    //The structs are held by CTCoreMessage so we don't have to free them
    [super dealloc];
}
@end
