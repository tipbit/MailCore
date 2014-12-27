//
//  CTNamespaces.h
//  MailCore
//
//  Created by Ewan Mellor on 12/27/14.
//
//

#import <Foundation/Foundation.h>


struct mailimap_namespace_data;


@interface CTNamespace : NSObject

@property (nonatomic, strong) NSString * prefix;
@property (nonatomic, assign) char delimiter;

@end


/**
 * Metadata for IMAP namespaces in the sense of RFC 2342.
 *
 * This doesn't include any info about Namespace_Response_Extensions,
 * because we don't use them.
 */
@interface CTNamespaces : NSObject

/**
 * CTNamespace array.
 */
@property (nonatomic, strong) NSArray * personal;

/**
 * CTNamespace array.
 */
@property (nonatomic, strong) NSArray * otherUsers;

/**
 * CTNamespace array.
 */
@property (nonatomic, strong) NSArray * shared;

-(instancetype)initWithNamespaceData:(struct mailimap_namespace_data *)data;

@end
