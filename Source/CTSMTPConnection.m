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

#import "CTSMTPConnection.h"
#import <libetpan/libetpan.h>
#import "CTCoreAddress.h"
#import "CTCoreMessage.h"
#import "MailCoreTypes.h"
#import "MailCoreUtilities.h"

#import "CTSMTP.h"
#import "CTESMTP.h"

//TODO Add more descriptive error messages using mailsmtp_strerror
@implementation CTSMTPConnection
+ (BOOL)sendMessage:(CTCoreMessage *)message server:(NSString *)server username:(NSString *)username
           password:(NSString *)password port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType
            useAuth:(BOOL)auth useOAuth2:(BOOL)useOAuth2 error:(NSError **)error {
    BOOL success;
    mailsmtp *smtp = NULL;
    smtp = mailsmtp_new(0, NULL);

    CTSMTP *smtpObj = [[CTESMTP alloc] initWithResource:smtp];
    if (connectionType == CTSMTPConnectionTypeStartTLS || connectionType == CTSMTPConnectionTypePlain) {
        success = [smtpObj connectToServer:server port:port];
    } else if (connectionType == CTSMTPConnectionTypeTLS) {
        success = [smtpObj connectWithTlsToServer:server port:port];
    } else {
        success = NO;
    }
    if (!success) {
        goto error;
    }
    if ([smtpObj helo] == NO) {
        /* The server didn't support ESMTP, so switching to STMP */
        [smtpObj release];
        smtpObj = [[CTSMTP alloc] initWithResource:smtp];
        success = [smtpObj helo];
        if (!success) {
            goto error;
        }
    }
    if (connectionType == CTSMTPConnectionTypeStartTLS) {
        success = [smtpObj startTLS];
        if (!success) {
            goto error;
        }
    }

    success = [CTSMTPConnection authenticate:smtpObj useAuth:auth useOAuth2:useOAuth2 username:username password:password server:server];
    if (!success) {
        goto error;
    }

    success = [smtpObj setFrom:[[[message from] anyObject] email]];
    if (!success) {
        goto error;
    }

    /* recipients */
    NSMutableSet *rcpts = [NSMutableSet set];
    [rcpts unionSet:[message to]];
    [rcpts unionSet:[message bcc]];
    [rcpts unionSet:[message cc]];
    success = [smtpObj setRecipients:rcpts];
    if (!success) {
        goto error;
    }
    
    NSSet *tmpBcc = message.bcc;

    // Temporarily wipe out BCC so it isn't sent with the message
    message.bcc = nil;
    
    /* data */
    NSData * data = [message renderData];
    if (data == nil) {
        goto error;
    }
    success = [smtpObj setData:data];
    mmap_string_unref((char *)data.bytes);
    
    message.bcc = tmpBcc;
    
    if (!success) {
        goto error;
    }
    
    mailsmtp_quit(smtp);
    mailsmtp_free(smtp);
    
    [smtpObj release];
    return YES;
error:
    if (error != NULL)
        *error = smtpObj.lastError;
    [smtpObj release];
    mailsmtp_free(smtp);
    return NO;
}

+ (BOOL)canConnectToServer:(NSString *)server username:(NSString *)username password:(NSString *)password
                      port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType
                   useAuth:(BOOL)auth useOAuth2:(BOOL)useOAuth2 timeout:(time_t)timeout error:(NSError **)error {
  BOOL success;
  mailsmtp *smtp = NULL;
  smtp = mailsmtp_new(0, NULL);
  mailsmtp_set_timeout(smtp, timeout);

    
  CTSMTP *smtpObj = [[CTESMTP alloc] initWithResource:smtp];
  if (connectionType == CTSMTPConnectionTypeStartTLS || connectionType == CTSMTPConnectionTypePlain) {
     success = [smtpObj connectToServer:server port:port];
  } else if (connectionType == CTSMTPConnectionTypeTLS) {
     success = [smtpObj connectWithTlsToServer:server port:port];
  } else {
     success = NO;
  }
  if (!success) {
    goto error;
  }
  if ([smtpObj helo] == NO) {
    /* The server didn't support ESMTP, so switching to STMP */
    [smtpObj release];
    smtpObj = [[CTSMTP alloc] initWithResource:smtp];
    success = [smtpObj helo];
    if (!success) {
      goto error;
    }
  }
  if (connectionType == CTSMTPConnectionTypeStartTLS) {
    success = [smtpObj startTLS];
    if (!success) {
      goto error;
    }
  }
  success = [CTSMTPConnection authenticate:smtpObj useAuth:auth useOAuth2:useOAuth2 username:username password:password server:server];
  if (!success) {
      *error = MailCoreCreateErrorFromSMTPCode(MAILSMTP_ERROR_AUTH_LOGIN);
      goto error;
  }

  mailsmtp_quit(smtp);
  mailsmtp_free(smtp);
    
  [smtpObj release];
  return YES;
error:
  if (error != NULL)
    *error = smtpObj.lastError;
  [smtpObj release];
  mailsmtp_free(smtp);
  return NO;
}


+(BOOL)authenticate:(CTSMTP *)smtpObj useAuth:(BOOL)auth useOAuth2:(BOOL)useOAuth2 username:(NSString *)username password:(NSString *)password server:(NSString *)server {
  if (useOAuth2) {
    return [smtpObj authenticateWithOAuth2:username token:password];
  }
  else if (auth) {
    return [smtpObj authenticateWithUsername:username password:password server:server];
  }
  else {
    return YES;
  }
}


@end
