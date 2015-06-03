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

#import <Foundation/Foundation.h>
#import <libetpan/libetpan.h>

typedef void (^CTProgressBlock)(size_t curr, size_t max);

@class CTMIME_Enumerator;

@interface CTMIME : NSObject {
    NSString *mContentType;
    BOOL mFetched;
    struct mailmime *mMime;
    struct mailmessage *mMessage;
    NSData *mData;
    NSError *lastError;
}
@property(nonatomic, retain) NSString *contentType;
@property(nonatomic, readonly) id content;
@property(nonatomic, retain) NSData *data;

@property(nonatomic) BOOL fetched;

/*
 If an error occurred (nil or return of NO) call this method to get the error
 */
@property(nonatomic, retain) NSError *lastError;


- (id)initWithData:(NSData *)data;

/**
 * Note that neither struct that you give here will be owned by this instance.
 * In other words, it's still your responsibility to free the given mime and message.
 */
- (id)initWithMIMEStruct:(struct mailmime *)mime
        forMessage:(struct mailmessage *)message;

/**
 * Note that this *mutates* the CTMIME instance -- some data is moved into the returned
 * struct mailmime to avoid a copy.  This means that you can't call buildMIMEStruct more
 * than once on the same instance and expect the same answer.
 *
 * @return A mailmime struct, yours to free with mailmime_free, or NULL on failure.
 * See self.lastError if there's a failure.
 */
- (struct mailmime *)buildMIMEStruct;

/**
 * Note that this *mutates* the CTMIME instance -- some data is used during rendering
 * to avoid a copy.  This means that you can't call renderData more than once on the same
 * instance and expect the same answer.
 *
 * You must call mmap_string_unref((char *)data.bytes) when you are done with the returned NSData.
 * See self.lastError if there's a failure.
 *
 * @return nil on failure.
 */
-(NSData *)renderData;

- (CTMIME_Enumerator *)mimeEnumerator;

- (BOOL)fetchPart;
- (BOOL)fetchPartWithProgress:(CTProgressBlock)block;
@end
