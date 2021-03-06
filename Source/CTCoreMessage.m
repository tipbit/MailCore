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

#import <libetpan/libetpan.h>
#import "CTCoreMessage.h"
#import "CTCoreAttachment.h"
#import "MailCoreTypes.h"
#import "CTCoreAddress.h"
#import "CTMIMEFactory.h"
#import "CTMIME_MessagePart.h"
#import "CTMIME_TextPart.h"
#import "CTMIME_MultiPart.h"
#import "CTMIME_SinglePart.h"
#import "CTBareAttachment.h"
#import "CTMIME_HtmlPart.h"
#import "MailCoreUtilities.h"


@interface CTCoreMessage () {
    /**
     * YES if this instance owns the content of myFields.  If that's the case,
     * then this class will free the fields in dealloc or renderData as appropriate.
     * If NO, then the content of myFields is assumed to be owned by myMessage, and
     * won't be freed.  (Also in that case the caller cannot use the field setters
     * to modify this instance.)
     */
    BOOL myFieldsIsOwnedByUs;
}

@end

@implementation CTCoreMessage
@synthesize mime=myParsedMIME, lastError, parentFolder;

- (id)init {
    self = [super init];
    if (self) {
        myFields = mailimf_single_fields_new(NULL);
        myFieldsIsOwnedByUs = YES;
    }
    return self;
}


- (id)initWithMessageStruct:(struct mailmessage *)message {
    self = [super init];
    if (self) {
        assert(message != NULL);
        myMessage = message;
        myFields = mailimf_single_fields_new(message->msg_fields);
    }
    return self;
}

- (id)initWithFileAtPath:(NSString *)path {
    return [self initWithString:[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]];
}

- (id)initWithString:(NSString *)msgData {
    struct mailmessage *msg = data_message_init((char *)[msgData cStringUsingEncoding:NSUTF8StringEncoding],
                                    [msgData lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    int err;
    struct mailmime *dummyMime;
    /* mailmessage_get_bodystructure will fill the mailmessage struct for us */
    err = mailmessage_get_bodystructure(msg, &dummyMime);
    if (err != MAIL_NO_ERROR) {
        return nil;
    }
    return [self initWithMessageStruct:msg];
}


- (void)dealloc {
    if (myMessage != NULL) {
        mailmessage_flush(myMessage);
        mailmessage_free(myMessage);
    }
    if (myFields != NULL) {
        if (myFieldsIsOwnedByUs) {
            mailimf_single_fields_free_fields(myFields);
        }
        mailimf_single_fields_free(myFields);
    }
    self.lastError = nil;
    self.parentFolder = nil;
    self.header = nil;
    [myParsedMIME release];
    [super dealloc];
}

- (NSError *)lastError {
    return lastError;
}

- (BOOL)hasBodyStructure {
    if (myParsedMIME == nil) {
        return NO;
    }
    return YES;
}

- (BOOL)fetchBodyStructure {
    if (myMessage == NULL) {
        return NO;
    }
    //we also fetch the header, because we want the receivedDate from it.
    [self fetchHeaderStructure];

    int err;
    struct mailmime *dummyMime;
    //Retrieve message mime and message field
    err = mailmessage_get_bodystructure(myMessage, &dummyMime);
    if (err != MAIL_NO_ERROR) {
        NSLog(@"Error in mailmessage_get_bodystructure. error num: %ld", (long)err);
        self.lastError = MailCoreCreateErrorFromIMAPCode(err);
        return NO;
    }
    
    CTMIME *oldMIME = myParsedMIME;
    myParsedMIME = [[CTMIMEFactory createMIMEWithMIMEStruct:[self messageStruct]->msg_mime
                        forMessage:[self messageStruct]] retain];
    [oldMIME release];

    return YES;
}


- (BOOL)fetchHeaderStructure{
    if (myMessage == NULL) {
        return NO;
    }
    
    int err;
    char *result;
    size_t result_len;
    //Retrieve message mime and message field
    err = mailmessage_fetch_header(myMessage, &result, &result_len);
    if (err != MAIL_NO_ERROR) {
        self.lastError = MailCoreCreateErrorFromIMAPCode(err);
        return NO;
    }
    
    self.header = [NSString stringWithCString:result encoding:NSASCIIStringEncoding];
    return YES;
}

- (void)setBodyStructure:(struct mailmime *)mime {
    CTMIME *oldMIME = myParsedMIME;
    myMessage->msg_mime = mime;
    myParsedMIME = [[CTMIMEFactory createMIMEWithMIMEStruct:[self messageStruct]->msg_mime
                                                 forMessage:[self messageStruct]] retain];
    [oldMIME release];
}

- (void)setFields:(struct mailimf_fields *)fields {
    if (myFields != NULL)
        mailimf_single_fields_free(myFields);
    myFields = mailimf_single_fields_new(fields);
}

- (NSString *)body {
    if (myFields == NULL || myParsedMIME == nil) {
        [self fetchBodyStructure];
    }
    NSMutableString *result = [NSMutableString string];
    BOOL success = [self _buildUpBodyText:myParsedMIME haveSeenOuterMessage:NO result:result];
    if (!success) {
        return nil;
    }
    return result;
}

- (NSString *)htmlBody {
    if (myFields == NULL || myParsedMIME == nil) {
        [self fetchBodyStructure];
    }
    NSMutableString *result = [NSMutableString string];
    BOOL success = [self _buildUpHtmlBodyText:myParsedMIME haveSeenOuterMessage:NO result:result];
    if (!success) {
        return nil;
    }
    return result;
}

- (NSString *)bodyPreferringPlainText:(BOOL *)isHTML {
    NSString *body = [self body];
    *isHTML = NO;
    if ([body length] == 0) {
        body = [self htmlBody];
        *isHTML = YES;
    }
    return body;
}


- (BOOL)_buildUpBodyText:(CTMIME *)mime haveSeenOuterMessage:(BOOL)haveSeenOuterMessage result:(NSMutableString *)result {
    if (mime == nil)
        return NO;

    if ([mime isKindOfClass:[CTMIME_MessagePart class]]) {
        return haveSeenOuterMessage ? YES : [self _buildUpBodyText:[mime content] haveSeenOuterMessage:YES result:result];
    }
    else if ([mime isKindOfClass:[CTMIME_TextPart class]]) {
        if ([[mime.contentType lowercaseString] rangeOfString:@"text/plain"].location != NSNotFound) {
            BOOL success = [(CTMIME_TextPart *)mime fetchPart];
            if (!success) {
                return NO;
            }
            NSString* y = [mime content];
            if(y == nil) {
                return NO;
            }
            [result appendString:y];
        }
    }
    else if ([mime isKindOfClass:[CTMIME_MultiPart class]]) {
        //TODO need to take into account the different kinds of multipart
        NSEnumerator *enumer = [[mime content] objectEnumerator];
        CTMIME *subpart;
        while ((subpart = [enumer nextObject])) {
            BOOL success = [self _buildUpBodyText:subpart haveSeenOuterMessage:YES result:result];
            if (!success) {
                return NO;
            }
        }
    }
    return YES;
}

- (BOOL)_buildUpHtmlBodyText:(CTMIME *)mime haveSeenOuterMessage:(BOOL)haveSeenOuterMessage result:(NSMutableString *)result {
    if (mime == nil)
        return NO;

    if ([mime isKindOfClass:[CTMIME_MessagePart class]]) {
        return haveSeenOuterMessage ? YES : [self _buildUpHtmlBodyText:[mime content] haveSeenOuterMessage:YES result:result];
    }
    else if ([mime isKindOfClass:[CTMIME_TextPart class]]) {
        if ([[mime.contentType lowercaseString] rangeOfString:@"text/html"].location != NSNotFound) {
            BOOL success = [(CTMIME_TextPart *)mime fetchPart];
            if (!success) {
                return NO;
            }
            
            NSString* y = [mime content];
            if(y == nil) {
                return NO;
            }
            [result appendString:y];
        }
    }
    else if ([mime isKindOfClass:[CTMIME_MultiPart class]]) {
        //TODO need to take into account the different kinds of multipart
        NSEnumerator *enumer = [[mime content] objectEnumerator];
        CTMIME *subpart;
        while ((subpart = [enumer nextObject])) {
            BOOL success = [self _buildUpHtmlBodyText:subpart haveSeenOuterMessage:YES result:result];
            if (!success) {
                return NO;
            }
        }
    }
    return YES;
}


- (void)setBody:(NSString *)body {
    CTMIME *oldMIME = myParsedMIME;
    CTMIME_TextPart *text = [CTMIME_TextPart mimeTextPartWithString:body];

    // If myParsedMIME is already a multi-part mime, just add it. otherwise replace it.
    //TODO: If setBody is called multiple times it will add text parts multiple times. Instead
    // it should find the existing text part (if there is one) and replace it
    if ([myParsedMIME isKindOfClass:[CTMIME_MultiPart class]]) {
        [(CTMIME_MultiPart *)myParsedMIME addMIMEPart:text];
    }
    else if ([myParsedMIME isKindOfClass:[CTMIME_MessagePart class]]) {
        CTMIME_MessagePart *msg;
        msg = (CTMIME_MessagePart *)myParsedMIME;
        CTMIME *sub = [msg content];
        
        
        CTMIME_MultiPart* multi;
        // Creat new multimime part if needed
        if ([sub isKindOfClass:[CTMIME_MultiPart class]]) {
            multi = (CTMIME_MultiPart *)sub;
            [multi addMIMEPart:text];
        }
        else if ([sub isKindOfClass:[CTMIME_HtmlPart class]])  {
            multi = [CTMIME_MultiPart mimeMultiPartAlternative];
            [multi addMIMEPart:sub];
            [msg setContent:multi];
            [multi addMIMEPart:text];
        }
    }
    else {
        CTMIME_MessagePart *messagePart = [CTMIME_MessagePart mimeMessagePartWithContent:text];
        myParsedMIME = [messagePart retain];
        [oldMIME release];
    }
}


- (void)setHTMLBody:(NSString *)body{
    CTMIME *oldMIME = myParsedMIME;
    
    CTMIME_HtmlPart *text = [CTMIME_HtmlPart mimeTextPartWithString:body];
    
    if ([myParsedMIME isKindOfClass:[CTMIME_MultiPart class]]) {
        [(CTMIME_MultiPart *)myParsedMIME addMIMEPart:text];
    }
    else if ([myParsedMIME isKindOfClass:[CTMIME_MessagePart class]]) {
        
        CTMIME_MessagePart *msg;
        msg = (CTMIME_MessagePart *)myParsedMIME;
        CTMIME *sub = [msg content];
        
        CTMIME_MultiPart* multi;
        // Creat new multimime part if needed
        if ([sub isKindOfClass:[CTMIME_MultiPart class]]) {
            multi = (CTMIME_MultiPart *)sub;
            [multi addMIMEPart:text];
        }
        else if ([sub isKindOfClass:[CTMIME_TextPart class]])  {
            multi = [CTMIME_MultiPart mimeMultiPartAlternative];
            [multi addMIMEPart:sub];
            [msg setContent:multi];
            [multi addMIMEPart:text];
        }
    }
    else {
        CTMIME_MessagePart *messagePart = [CTMIME_MessagePart mimeMessagePartWithContent:text];
        myParsedMIME = [messagePart retain];
        [oldMIME release];
    }
}

- (NSArray *)attachments {
    NSMutableArray *attachments = [NSMutableArray array];

    BOOL haveSeenOuterMessage = NO;
    CTMIME_Enumerator *enumerator = [myParsedMIME mimeEnumerator];
    CTMIME *mime;
    while ((mime = [enumerator nextObject])) {

        if ([mime isKindOfClass:[CTMIME_SinglePart class]]) {
            CTMIME_SinglePart *singlePart = (CTMIME_SinglePart *)mime;
            if (singlePart.attached || (singlePart.contentId != nil && [CTCoreAttachment isInlineContentType:singlePart.contentType])) {
                CTBareAttachment *attach = [[CTBareAttachment alloc] initWithMIMESinglePart:singlePart];
                [attachments addObject:attach];
                [attach release];
            }
        }
        else if ([mime isKindOfClass:[CTMIME_MessagePart class]]) {
            CTMIME_MessagePart * msg = (CTMIME_MessagePart *)mime;
            if (haveSeenOuterMessage) {
                // This is not the outermost message part, so it must be an attached message.
                CTBareAttachment * attach = [[CTBareAttachment alloc] initWithMIMEMessagePart:msg];
                [attachments addObject:attach];
                [attach release];
            }
            else {
                // enumerator is recursing across all attachments, so there's no need for us to recurse here.
                haveSeenOuterMessage = YES;
            }
        }
    }

    return attachments;
}

- (void)addAttachment:(CTCoreAttachment *)attachment {
    CTMIME_MultiPart *multi=nil;
    CTMIME_MessagePart *msg=nil;
    CTMIME_MultiPart * subMulti=nil;

    if ([myParsedMIME isKindOfClass:[CTMIME_MessagePart class]]) {
        msg = (CTMIME_MessagePart *)myParsedMIME;
        CTMIME *sub = [msg content];


        // Creat new multimime part if needed
        if ([sub isKindOfClass:[CTMIME_MultiPart class]]) {
            multi = (CTMIME_MultiPart *)sub;
            if ([multi.contentType isEqualToString:@"multipart/alternative"]) {
                if (((CTBareAttachment*)attachment).contentId.length) {
                    subMulti = [CTMIME_MultiPart mimeMultiPartRelated];
                }
                else  {
                    subMulti = [CTMIME_MultiPart mimeMultiPart];
                }
                
                [subMulti addMIMEPart:sub];
                [msg setContent:subMulti];
            }
            
        } else {
            if (((CTBareAttachment*)attachment).contentId.length) {
                multi = [CTMIME_MultiPart mimeMultiPartRelated];
            }
            else  {
                multi = [CTMIME_MultiPart mimeMultiPart];
            }
            [multi addMIMEPart:sub];
            [msg setContent:multi];
        }

        // add new SinglePart which encodes the attachment in base64
        CTMIME_SinglePart *attpart = [CTMIME_SinglePart mimeSinglePartWithData:[attachment data]];
        attpart.contentType = [attachment contentType];
        attpart.filename = [attachment filename];
        attpart.contentId = ((CTBareAttachment*)attachment).contentId;

        if (subMulti!=nil) {
            [subMulti addMIMEPart:attpart];
        }
        else
            [multi addMIMEPart:attpart];
    }
}

- (NSString *)subject {
    if (myFields->fld_subject == NULL)
        return nil;
    NSString *decodedSubject = MailCoreDecodeMIMEPhrase(myFields->fld_subject->sbj_value);
    if (decodedSubject == nil)
        return nil;
    return decodedSubject;
}

- (void)setSubject:(NSString *)subject {
    struct mailimf_subject *subjectStruct;

    subjectStruct = mailimf_subject_new(strdup([subject cStringUsingEncoding:NSUTF8StringEncoding]));
    if (myFields->fld_subject != NULL)
        mailimf_subject_free(myFields->fld_subject);
    myFields->fld_subject = subjectStruct;
}

- (struct mailimf_date_time*)libetpanDateTime {    
    if(!myFields || !myFields->fld_orig_date || !myFields->fld_orig_date->dt_date_time)
        return NULL;

    return myFields->fld_orig_date->dt_date_time;
}

- (NSTimeZone*)senderTimeZone {
    struct mailimf_date_time *d;

    if((d = [self libetpanDateTime]) == NULL)
        return nil;

    NSInteger timezoneOffsetInSeconds = 3600*d->dt_zone/100;

    return [NSTimeZone timeZoneForSecondsFromGMT:timezoneOffsetInSeconds];
}

- (NSDate *)senderDate {
    if ( myFields->fld_orig_date == NULL) {
        return nil;
    } else {
        struct mailimf_date_time *d;

        if ((d = [self libetpanDateTime]) == NULL)
            return nil;

        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = [self senderTimeZone];
        NSDateComponents *comps = [[NSDateComponents alloc] init];

        [comps setYear:d->dt_year];
        [comps setMonth:d->dt_month];
        [comps setDay:d->dt_day];
        [comps setHour:d->dt_hour];
        [comps setMinute:d->dt_min];
        [comps setSecond:d->dt_sec];

        NSDate *messageDate = [calendar dateFromComponents:comps];

        [comps release];
        [calendar release];

        return messageDate;
    }
}

- (BOOL)isUnread {
    return ![self isFlagSet:MAIL_FLAG_SEEN withDefault:YES];
}

- (BOOL)isDeleted {
    return [self isFlagSet:MAIL_FLAG_DELETED withDefault:NO];
}

- (BOOL)isStarred {
    return [self isFlagSet:MAIL_FLAG_FLAGGED withDefault:NO];
}

- (BOOL)isFlagSet:(NSUInteger)flag withDefault:(BOOL)def {
    struct mail_flags *flags = myMessage ? myMessage->msg_flags : NULL;
    return flags == NULL ? def : ((flags->fl_flags & flag) != 0);
}

- (BOOL)isNew {
    struct mail_flags *flags = myMessage ? myMessage->msg_flags : NULL;
    if (flags != NULL) {
        BOOL flag_seen = ((flags->fl_flags & MAIL_FLAG_SEEN) != 0);
        BOOL flag_new = ((flags->fl_flags & MAIL_FLAG_NEW) != 0);
        return !flag_seen && flag_new;
    }
    return NO;
}

- (NSString *)messageId {
    if (myFields->fld_message_id != NULL) {
        char *value = myFields->fld_message_id->mid_value;
        return [NSString stringWithCString:value encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (NSUInteger)uid {
    if (myMessage && myMessage->msg_uid) {
        NSString *uidString = [[NSString alloc] initWithCString:myMessage->msg_uid encoding:NSASCIIStringEncoding];
        NSUInteger uid = (NSUInteger)[[[uidString componentsSeparatedByString:@"-"] objectAtIndex:1] intValue];
        [uidString release];
        return uid;
    }
    return 0;
}

- (uint64_t)gm_msgid {
    if (myMessage && myMessage->msg_gm_msgid) {
        return myMessage->msg_gm_msgid;
    }
    return 0;
}

- (NSUInteger)messageSize {
    return [self messageStruct]->msg_size;
}

- (NSUInteger)flags {
    if (myMessage != NULL && myMessage->msg_flags != NULL) {
        return myMessage->msg_flags->fl_flags;
    }
    return 0;
}

- (NSArray *)extionsionFlags {
  if (myMessage != NULL && myMessage->msg_flags != NULL) {
    return MailCoreStringArrayFromClist(myMessage->msg_flags->fl_extension);
  }
  return nil;
}

- (NSUInteger)sequenceNumber {
    return mySequenceNumber;
}

- (void)setSequenceNumber:(NSUInteger)sequenceNumber {
    mySequenceNumber = sequenceNumber;
}


- (NSSet *)from {
    if (myFields->fld_from == NULL)
        return nil;

    return [self _addressListFromMailboxList:myFields->fld_from->frm_mb_list];
}


- (void)setFrom:(NSSet *)addresses {
    struct mailimf_mailbox_list *imf = [self _mailboxListFromAddressList:addresses];
    if (myFields->fld_from != NULL)
        mailimf_from_free(myFields->fld_from);
    myFields->fld_from = mailimf_from_new(imf);
}


- (CTCoreAddress *)sender {
    if (myFields->fld_sender == NULL)
        return nil;

    return [self _addressFromMailbox:myFields->fld_sender->snd_mb];
}


- (NSSet *)to {
    if (myFields->fld_to == NULL)
        return nil;
    else
        return [self _addressListFromIMFAddressList:myFields->fld_to->to_addr_list];
}


- (void)setTo:(NSSet *)addresses {
    struct mailimf_address_list *imf = [self _IMFAddressListFromAddresssList:addresses];

    if (myFields->fld_to != NULL) {
        mailimf_address_list_free(myFields->fld_to->to_addr_list);
        myFields->fld_to->to_addr_list = imf;
    }
    else
        myFields->fld_to = mailimf_to_new(imf);
}

- (NSArray *)inReplyTo {
    if (myFields->fld_in_reply_to == NULL)
        return nil;
    else
        return MailCoreStringArrayFromClist(myFields->fld_in_reply_to->mid_list);
}


- (void)setInReplyTo:(NSArray *)messageIds {
	struct mailimf_in_reply_to *imf = (messageIds.count == 0 ? NULL : mailimf_in_reply_to_new(MailCoreClistFromStringArray(messageIds)));

    if (myFields->fld_in_reply_to != NULL) {
        mailimf_in_reply_to_free(myFields->fld_in_reply_to);
    }
    myFields->fld_in_reply_to = imf;
}


- (NSArray *)references {
    if (myFields->fld_references == NULL)
        return nil;
    else
        return MailCoreStringArrayFromClist(myFields->fld_references->mid_list);
}


- (void)setReferences:(NSArray *)messageIds {
    struct mailimf_references *imf = (messageIds.count == 0 ? NULL : mailimf_references_new(MailCoreClistFromStringArray(messageIds)));

    if (myFields->fld_references != NULL) {
        mailimf_references_free(myFields->fld_references);
    }
    myFields->fld_references = imf;
}


- (NSSet *)cc {
    if (myFields->fld_cc == NULL)
        return nil;
    else
        return [self _addressListFromIMFAddressList:myFields->fld_cc->cc_addr_list];
}


- (void)setCc:(NSSet *)addresses {
    struct mailimf_address_list *imf = [self _IMFAddressListFromAddresssList:addresses];
    if (myFields->fld_cc != NULL) {
        mailimf_address_list_free(myFields->fld_cc->cc_addr_list);
        myFields->fld_cc->cc_addr_list = imf;
    }
    else
        myFields->fld_cc = mailimf_cc_new(imf);
}


- (NSSet *)bcc {
    if (myFields->fld_bcc == NULL)
        return nil;
    else
        return [self _addressListFromIMFAddressList:myFields->fld_bcc->bcc_addr_list];
}


- (void)setBcc:(NSSet *)addresses {
    struct mailimf_address_list *imf = [self _IMFAddressListFromAddresssList:addresses];
    if (myFields->fld_bcc != NULL) {
        mailimf_address_list_free(myFields->fld_bcc->bcc_addr_list);
        myFields->fld_bcc->bcc_addr_list = imf;
    }
    else
        myFields->fld_bcc = mailimf_bcc_new(imf);
}


- (NSSet *)replyTo {
    if (myFields->fld_reply_to == NULL)
        return nil;
    else
        return [self _addressListFromIMFAddressList:myFields->fld_reply_to->rt_addr_list];
}


- (void)setReplyTo:(NSSet *)addresses {
    struct mailimf_address_list *imf = [self _IMFAddressListFromAddresssList:addresses];
    if (myFields->fld_reply_to != NULL) {
        mailimf_address_list_free(myFields->fld_reply_to->rt_addr_list);
        myFields->fld_reply_to->rt_addr_list = imf;
    }
    else
        myFields->fld_reply_to = mailimf_reply_to_new(imf);
}


- (void)_render {
    CTMIME *msgPart = myParsedMIME;

    if ([myParsedMIME isKindOfClass:[CTMIME_MessagePart class]]) {
        /* It's a message part, so let's set it's fields */
        struct mailimf_fields *fields;
        struct mailimf_mailbox *sender = (myFields->fld_sender != NULL) ? (myFields->fld_sender->snd_mb) : NULL;
        struct mailimf_mailbox_list *from = (myFields->fld_from != NULL) ? (myFields->fld_from->frm_mb_list) : NULL;
        struct mailimf_address_list *replyTo = (myFields->fld_reply_to != NULL) ? (myFields->fld_reply_to->rt_addr_list) : NULL;
        struct mailimf_address_list *to = (myFields->fld_to != NULL) ? (myFields->fld_to->to_addr_list) : NULL;
        struct mailimf_address_list *cc = (myFields->fld_cc != NULL) ? (myFields->fld_cc->cc_addr_list) : NULL;
        struct mailimf_address_list *bcc = (myFields->fld_bcc != NULL) ? (myFields->fld_bcc->bcc_addr_list) : NULL;
        clist *inReplyTo = (myFields->fld_in_reply_to != NULL) ? (myFields->fld_in_reply_to->mid_list) : NULL;
        clist *references = (myFields->fld_references != NULL) ? (myFields->fld_references->mid_list) : NULL;
        char *subject = (myFields->fld_subject != NULL) ? (myFields->fld_subject->sbj_value) : NULL;

        fields = mailimf_fields_new_with_data(from, sender, replyTo, to, cc, bcc, inReplyTo, references, subject);
        
        if (self->mailPriority != 0) {
            char * xPriorityValue;
            char * rfcPriorityValue;
            switch (self->mailPriority) {
                case CTCoreMessageUrgentPriority: {
                    xPriorityValue = "1";
                    rfcPriorityValue = "urgent";
                    break;
                }
                case CTCoreMessageNormalPriority: {
                    xPriorityValue = "3";
                    rfcPriorityValue = "normal";
                    break;
                }
                case CTCoreMessageNonUrgentPriority: {
                    xPriorityValue = "5";
                    rfcPriorityValue = "non-urgent";
                    break;
                }
                    
                default:
                    break;
            }

            struct mailimf_optional_field * priority = mailimf_optional_field_new("X-Priority", xPriorityValue);
            
            struct mailimf_field * priorityField = mailimf_field_new(MAILIMF_FIELD_OPTIONAL_FIELD, NULL, NULL, NULL,
                                                                     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                                                                     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                                                                     NULL, NULL, priority);
            mailimf_fields_add(fields, priorityField);
            
            priority = mailimf_optional_field_new("Priority", rfcPriorityValue);
            priorityField = mailimf_field_new(MAILIMF_FIELD_OPTIONAL_FIELD, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                                              NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                                              NULL, NULL, priority);
            
            mailimf_fields_add(fields, priorityField);
        }

        if (self.threadTopic != nil) {
            mailimf_fields_add(fields, mailimf_field_new_custom(strdup("Thread-Topic"), strdup(self.threadTopic.UTF8String)));
        }

        // This transfers ownership of fields to CTMIME_MessagePart.
        [(CTMIME_MessagePart *)msgPart setIMFFields:fields];
        if (myFieldsIsOwnedByUs) {
            // We own myFields, but we have transferred all the important
            // bits of that structure to CTMIME_MessagePart via the
            // mailimf_fields_new_with_data call.  We therefore need to
            // free the holding structures that remain (without freeing
            // any of the real data, because CTMIME_MessagePart will do that).
#define FREE_AND_NULL(__f) \
    free(myFields->__f); \
    myFields->__f = NULL;
            FREE_AND_NULL(fld_sender);
            FREE_AND_NULL(fld_from);
            FREE_AND_NULL(fld_reply_to);
            FREE_AND_NULL(fld_to);
            FREE_AND_NULL(fld_cc);
            FREE_AND_NULL(fld_bcc);
            FREE_AND_NULL(fld_in_reply_to);
            FREE_AND_NULL(fld_references);
            FREE_AND_NULL(fld_subject);
#undef FREE_AND_NULL
        }
    }
}

- (NSData *)renderData {
    [self _render];
    NSData * result = [myParsedMIME renderData];
    if (result == nil) {
        self.lastError = myParsedMIME.lastError;
    }
    return result;
}

- (NSData *)messageAsEmlx {
    NSString *msgContent = [[self rfc822] stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    NSData *msgContentAsData = [msgContent dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *emlx = [NSMutableData data];
    [emlx appendData:[[NSString stringWithFormat:@"%-10d\n", (uint32_t)msgContentAsData.length] dataUsingEncoding:NSUTF8StringEncoding]];
    [emlx appendData:msgContentAsData];


    struct mail_flags *flagsStruct = myMessage ? myMessage->msg_flags : NULL;
    uint64_t flags = 0;
    if (flagsStruct != NULL) {
        BOOL seen = (flagsStruct->fl_flags & CTFlagSeen) > 0;
        flags |= seen << 0;
        BOOL answered = (flagsStruct->fl_flags & CTFlagAnswered) > 0;
        flags |= answered << 2;
        BOOL flagged = (flagsStruct->fl_flags & CTFlagFlagged) > 0;
        flags |= flagged << 4;
        BOOL forwarded = (flagsStruct->fl_flags & CTFlagForwarded) > 0;
        flags |= forwarded << 8;
    }

    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [dictionary setValue:[NSNumber numberWithDouble:[[self senderDate] timeIntervalSince1970]] forKey:@"date-sent"];
    [dictionary setValue:[NSNumber numberWithUnsignedLongLong:flags] forKey:@"flags"];
    [dictionary setValue:[self subject] forKey:@"subject"];

    NSError *error;
    NSData *propertyList = [NSPropertyListSerialization dataWithPropertyList:dictionary
                                                                      format:NSPropertyListXMLFormat_v1_0
                                                                     options:0
                                                                       error:&error];
    [emlx appendData:propertyList];
    return emlx;
}

- (NSString *)rfc822 {
    char *result = NULL;
    NSString *nsresult;
    int r = mailimap_fetch_rfc822([self imapSession], (uint32_t)[self sequenceNumber], &result);
    if (r == MAIL_NO_ERROR) {
        nsresult = [[NSString alloc] initWithCString:result encoding:NSUTF8StringEncoding];
    } else {
        self.lastError = MailCoreCreateErrorFromIMAPCode(r);
        return nil;
    }
    mailimap_msg_att_rfc822_free(result);
    return [nsresult autorelease];
}

- (NSString *)rfc822Header {
    char *result = NULL;
    NSString *nsresult;
    int r = mailimap_fetch_rfc822_header([self imapSession], (uint32_t)[self sequenceNumber], &result);
    if (r == MAIL_NO_ERROR) {
        nsresult = [[NSString alloc] initWithCString:result encoding:NSUTF8StringEncoding];
    } else {
        self.lastError = MailCoreCreateErrorFromIMAPCode(r);
        return nil;
    }
    mailimap_msg_att_rfc822_free(result);
    return [nsresult autorelease];
}

- (void)setMailPriority:(CTCoreMessagePriority)priority {
    mailPriority = priority;
}

- (struct mailmessage *)messageStruct {
    return myMessage;
}

- (mailimap *)imapSession; {
    struct imap_cached_session_state_data * cached_data;
    struct imap_session_state_data * data;
    mailsession *session = [self messageStruct]->msg_session;

    if (strcasecmp(session->sess_driver->sess_name, "imap-cached") == 0) {
        cached_data = session->sess_data;
        session = cached_data->imap_ancestor;
    }

    data = session->sess_data;
    return data->imap_session;
}

- (CTCoreAddress *)_addressFromMailbox:(struct mailimf_mailbox *)mailbox; {
    CTCoreAddress *address = [CTCoreAddress address];
    if (mailbox == NULL) {
        return address;
    }
    if (mailbox->mb_display_name != NULL) {
        NSString *decodedName = MailCoreDecodeMIMEPhrase(mailbox->mb_display_name);
        if (decodedName == nil) {
            decodedName = @"";
        }
        [address setName:decodedName];
    }
    if (mailbox->mb_addr_spec != NULL) {
        [address setEmail:[NSString stringWithCString:mailbox->mb_addr_spec encoding:NSUTF8StringEncoding]];
    }
    return address;
}


- (NSSet *)_addressListFromMailboxList:(struct mailimf_mailbox_list *)mailboxList; {
    clist *list;
    clistiter * iter;
    struct mailimf_mailbox *address;
    NSMutableSet *addressSet = [NSMutableSet set];

    if (mailboxList == NULL)
        return addressSet;

    list = mailboxList->mb_list;
    for(iter = clist_begin(list); iter != NULL; iter = clist_next(iter)) {
        address = clist_content(iter);
        [addressSet addObject:[self _addressFromMailbox:address]];
    }
    return addressSet;
}


- (struct mailimf_mailbox_list *)_mailboxListFromAddressList:(NSSet *)addresses {
    struct mailimf_mailbox_list *imfList = mailimf_mailbox_list_new_empty();
    NSEnumerator *objEnum = [addresses objectEnumerator];
    CTCoreAddress *address;
    int err;
    const char *addressName;
    const char *addressEmail;

    while((address = [objEnum nextObject])) {
        addressName = [[address name] cStringUsingEncoding:NSUTF8StringEncoding];
        addressEmail = [[address email] cStringUsingEncoding:NSUTF8StringEncoding];
        err =  mailimf_mailbox_list_add_mb(imfList, strdup(addressName), strdup(addressEmail));
        assert(err == 0);
    }
    return imfList;
}


- (NSSet *)_addressListFromIMFAddressList:(struct mailimf_address_list *)imfList {
    clist *list;
    clistiter * iter;
    struct mailimf_address *address;
    NSMutableSet *addressSet = [NSMutableSet set];

    if (imfList == NULL)
        return addressSet;

    list = imfList->ad_list;
    for(iter = clist_begin(list); iter != NULL; iter = clist_next(iter)) {
        address = clist_content(iter);
        /* Check to see if it's a solo address a group */
        if (address->ad_type == MAILIMF_ADDRESS_MAILBOX) {
            [addressSet addObject:[self _addressFromMailbox:address->ad_data.ad_mailbox]];
        }
        else {
            if (address->ad_data.ad_group->grp_mb_list != NULL)
                [addressSet unionSet:[self _addressListFromMailboxList:address->ad_data.ad_group->grp_mb_list]];
        }
    }
    return addressSet;
}


- (struct mailimf_address_list *)_IMFAddressListFromAddresssList:(NSSet *)addresses {
    struct mailimf_address_list *imfList = mailimf_address_list_new_empty();

    NSEnumerator *objEnum = [addresses objectEnumerator];
    CTCoreAddress *address;
    int err;
    const char *addressName;
    const char *addressEmail;

    while((address = [objEnum nextObject])) {
        addressName = [[address name] cStringUsingEncoding:NSUTF8StringEncoding];
        addressEmail = [[address email] cStringUsingEncoding:NSUTF8StringEncoding];
        err =  mailimf_address_list_add_mb(imfList, strdup(addressName), strdup(addressEmail));
        assert(err == 0);
    }
    return imfList;
}


@end
