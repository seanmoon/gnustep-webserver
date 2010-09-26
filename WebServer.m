/** 
   Copyright (C) 2004 Free Software Foundation, Inc.
   
   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date:	June 2004
   
   This file is part of the WebServer Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.

   $Date$ $Revision$
   */ 

#include <Foundation/Foundation.h>
#include <Performance/GSThreadPool.h>
#include "WebServer.h"
#include "Internal.h"

#define	MAXCONNECTIONS	10000

static	Class	NSArrayClass = Nil;
static	Class	NSDataClass = Nil;
static	Class	NSDateClass = Nil;
static	Class	NSDictionaryClass = Nil;
static	Class	NSMutableArrayClass = Nil;
static	Class	NSMutableDataClass = Nil;
static	Class	NSMutableDictionaryClass = Nil;
static	Class	NSMutableStringClass = Nil;
static	Class	NSStringClass = Nil;
static	Class	GSMimeDocumentClass = Nil;
static	Class	WebServerHeaderClass = Nil;
static NSZone	*defaultMallocZone = 0;

#define	Alloc(X)	[(X) allocWithZone: defaultMallocZone]

@implementation	WebServer

+ (void) initialize
{
  if (NSDataClass == Nil)
    {
      defaultMallocZone = NSDefaultMallocZone();
      NSStringClass = [NSString class];
      NSArrayClass = [NSArray class];
      NSDataClass = [NSData class];
      NSDateClass = [NSDate class];
      NSDictionaryClass = [NSDictionary class];
      NSMutableArrayClass = [NSMutableArray class];
      NSMutableDataClass = [NSMutableData class];
      NSMutableDictionaryClass = [NSMutableDictionary class];
      NSMutableStringClass = [NSMutableString class];
      GSMimeDocumentClass = [GSMimeDocument class];
      WebServerHeaderClass = [WebServerHeader class];
    }
}

static NSUInteger
unescapeData(const uint8_t *bytes, NSUInteger length, uint8_t *buf)
{
  NSUInteger	to = 0;
  NSUInteger	from = 0;

  while (from < length)
    {
      uint8_t	c = bytes[from++];

      if (c == '+')
	{
	  c = ' ';
	}
      else if (c == '%' && from < length - 1)
	{
	  uint8_t	tmp;

	  c = 0;
	  tmp = bytes[from++];
	  if (tmp <= '9' && tmp >= '0')
	    {
	      c = tmp - '0';
	    }
	  else if (tmp <= 'F' && tmp >= 'A')
	    {
	      c = tmp + 10 - 'A';
	    }
	  else if (tmp <= 'f' && tmp >= 'a')
	    {
	      c = tmp + 10 - 'a';
	    }
	  else
	    {
	      c = 0;
	    }
	  c <<= 4;
	  tmp = bytes[from++];
	  if (tmp <= '9' && tmp >= '0')
	    {
	      c += tmp - '0';
	    }
	  else if (tmp <= 'F' && tmp >= 'A')
	    {
	      c += tmp + 10 - 'A';
	    }
	  else if (tmp <= 'f' && tmp >= 'a')
	    {
	      c += tmp + 10 - 'a';
	    }
	  else
	    {
	      c = 0;
	    }
	}
      buf[to++] = c;
    }
  return to;
}

+ (NSURL*) baseURLForRequest: (GSMimeDocument*)request
{
  NSString	*scheme = [[request headerNamed: @"x-http-scheme"] value];
  NSString	*host = [[request headerNamed: @"host"] value];
  NSString	*path = [[request headerNamed: @"x-http-path"] value];
  NSString	*query = [[request headerNamed: @"x-http-query"] value];
  NSString	*str;
  NSURL		*url;

  /* An HTTP/1.1 request MUST contain the host header, but older requests
   * may not ... in which case we have to use our local IP address and port.
   */
  if ([host length] == 0)
    {
      host = [NSString stringWithFormat: @"%@:%@",
	[[request headerNamed: @"x-local-address"] value],
	[[request headerNamed: @"x-local-port"] value]];
    }

  if ([query length] > 0)
    {
      str = [NSString stringWithFormat: @"%@://%@%@?%@",
	scheme, host, path, query];
    }
  else
    {
      str = [NSString stringWithFormat: @"%@://%@%@", scheme, host, path];
    }

  url = [NSURL URLWithString: str];
  return url;
}

+ (NSUInteger) decodeURLEncodedForm: (NSData*)data
			     into: (NSMutableDictionary*)dict
{
  const uint8_t		*bytes = (const uint8_t	*)[data bytes];
  NSUInteger		length = [data length];
  NSUInteger		pos = 0;
  NSUInteger		fields = 0;

  while (pos < length)
    {
      NSUInteger	keyStart = pos;
      NSUInteger	keyEnd;
      NSUInteger	valStart;
      NSUInteger	valEnd;
      uint8_t		*buf;
      NSUInteger	buflen;
      BOOL		escape = NO;
      NSData		*d;
      NSString		*k;
      NSMutableArray	*a;

      while (pos < length && bytes[pos] != '&')
	{
	  pos++;
	}
      valEnd = pos;
      if (pos < length)
	{
	  pos++;	// Step past '&'
	}

      keyEnd = keyStart;
      while (keyEnd < pos && bytes[keyEnd] != '=')
	{
	  if (bytes[keyEnd] == '%' || bytes[keyEnd] == '+')
	    {
	      escape = YES;
	    }
	  keyEnd++;
	}

      if (escape == YES)
	{
	  buf = NSZoneMalloc(NSDefaultMallocZone(), keyEnd - keyStart);
	  buflen = unescapeData(&bytes[keyStart], keyEnd - keyStart, buf);
	  d = [Alloc(NSDataClass) initWithBytesNoCopy: buf
						length: buflen
					  freeWhenDone: YES];
	}
      else
	{
	  d = [Alloc(NSDataClass) initWithBytesNoCopy: (void*)&bytes[keyStart]
						length: keyEnd - keyStart
					  freeWhenDone: NO];
	}
      k = [Alloc(NSStringClass) initWithData: d
				     encoding: NSUTF8StringEncoding];
      if (k == nil)
	{
	  [NSException raise: NSInvalidArgumentException
		      format: @"Bad UTF-8 form data (key of field %d)", fields];
	}
      RELEASE(d);

      valStart = keyEnd;
      if (valStart < pos)
	{
	  valStart++;	// Step past '='
	}
      if (valStart < valEnd)
	{
	  buf = NSZoneMalloc(NSDefaultMallocZone(), valEnd - valStart);
	  buflen = unescapeData(&bytes[valStart], valEnd - valStart, buf);
	  d = [Alloc(NSDataClass) initWithBytesNoCopy: buf
						length: buflen
					  freeWhenDone: YES];
	}
      else
	{
	  d = [NSDataClass new];
	}
      a = [dict objectForKey: k];
      if (a == nil)
	{
	  a = [Alloc(NSMutableArrayClass) initWithCapacity: 1];
	  [dict setObject: a forKey: k];
	  RELEASE(a);
	}
      [a addObject: d];
      RELEASE(d);
      RELEASE(k);
      fields++;
    }
  return fields;
}

static NSMutableData*
escapeData(const uint8_t *bytes, NSUInteger length, NSMutableData *d)
{
  uint8_t	*dst;
  NSUInteger	spos = 0;
  NSUInteger	dpos = [d length];

  [d setLength: dpos + 3 * length];
  dst = (uint8_t *)[d mutableBytes];
  while (spos < length)
    {
      uint8_t		c = bytes[spos++];
      NSUInteger	hi;
      NSUInteger	lo;

      switch (c)
	{
	  case ',':
	  case ';':
	  case '"':
	  case '\'':
	  case '&':
	  case '=':
	  case '(':
	  case ')':
	  case '<':
	  case '>':
	  case '?':
	  case '#':
	  case '{':
	  case '}':
	  case '%':
	  case ' ':
	  case '+':
	    dst[dpos++] = '%';
	    hi = (c & 0xf0) >> 4;
	    dst[dpos++] = (hi > 9) ? 'A' + hi - 10 : '0' + hi;
	    lo = (c & 0x0f);
	    dst[dpos++] = (lo > 9) ? 'A' + lo - 10 : '0' + lo;
	    break;

	  default:
	    if (c < ' ' || c > 127)
	      {
		dst[dpos++] = '%';
		hi = (c & 0xf0) >> 4;
		dst[dpos++] = (hi > 9) ? 'A' + hi - 10 : '0' + hi;
		lo = (c & 0x0f);
		dst[dpos++] = (lo > 9) ? 'A' + lo - 10 : '0' + lo;
	      }
	    else
	      {
		dst[dpos++] = c;
	      }
	    break;
	}
    }
  [d setLength: dpos];
  return d;
}

+ (NSUInteger) encodeURLEncodedForm: (NSDictionary*)dict
			       into: (NSMutableData*)data
{
  CREATE_AUTORELEASE_POOL(arp);
  NSEnumerator		*keyEnumerator;
  id			key;
  NSUInteger		valueCount = 0;
  NSMutableData		*md = [NSMutableDataClass dataWithCapacity: 100];

  keyEnumerator = [dict keyEnumerator];
  while ((key = [keyEnumerator nextObject]) != nil)
    {
      id		values = [dict objectForKey: key];
      NSData		*keyData;
      NSEnumerator	*valueEnumerator;
      id		value;

      if ([key isKindOfClass: NSDataClass] == YES)
	{
	  keyData = key;
	}
      else
	{
	  key = [key description];
	  keyData = [key dataUsingEncoding: NSUTF8StringEncoding];
	}
      [md setLength: 0];
      escapeData([keyData bytes], [keyData length], md);
      keyData = md;

      if ([values isKindOfClass: NSArrayClass] == NO)
        {
	  values = [NSArrayClass arrayWithObject: values];
	}

      valueEnumerator = [values objectEnumerator];

      while ((value = [valueEnumerator nextObject]) != nil)
	{
	  NSData	*valueData;

	  if ([data length] > 0)
	    {
	      [data appendBytes: "&" length: 1];
	    }
	  [data appendData: keyData];
	  [data appendBytes: "=" length: 1];
	  if ([value isKindOfClass: NSDataClass] == YES)
	    {
	      valueData = value;
	    }
	  else
	    {
	      value = [value description];
	      valueData = [value dataUsingEncoding: NSUTF8StringEncoding];
	    }
	  escapeData([valueData bytes], [valueData length], data);
	  valueCount++;
	}
    }
  RELEASE(arp);
  return valueCount;
}

+ (NSString*) escapeHTML: (NSString*)str
{
  NSUInteger	length = [str length];
  NSUInteger	output = 0;
  unichar	*from;
  NSUInteger	i = 0;
  BOOL		escape = NO;

  if (length == 0)
    {
      return str;
    }
  from = NSZoneMalloc (NSDefaultMallocZone(), sizeof(unichar) * length);
  [str getCharacters: from];

  for (i = 0; i < length; i++)
    {
      unichar	c = from[i];

      if ((c >= 0x20 && c <= 0xd7ff)
	|| c == 0x9 || c == 0xd || c == 0xa
	|| (c >= 0xe000 && c <= 0xfffd))
	{
	  switch (c)
	    {
	      case '"':
	      case '\'':
		output += 6;
		escape = YES;
	        break;

	      case '&':
		output += 5;
		escape = YES;
	        break;

	      case '<':
	      case '>':
		output += 4;
		escape = YES;
	        break;

	      default:
		/*
		 * For non-ascii characters, we can use &#nnnn; escapes
		 */
		if (c > 127)
		  {
		    output += 5;
		    while (c >= 1000)
		      {
			output++;
			c /= 10;
		      }
		    escape = YES;
		  }
		output++;
		break;
	    }
	}
      else
	{
	  escape = YES;	// Need to remove bad characters
	}
    }

  if (escape == YES)
    {
      unichar	*to;
      NSUInteger	j = 0;

      to = NSZoneMalloc (NSDefaultMallocZone(), sizeof(unichar) * output);

      for (i = 0; i < length; i++)
	{
	  unichar	c = from[i];

	  if ((c >= 0x20 && c <= 0xd7ff)
	    || c == 0x9 || c == 0xd || c == 0xa
	    || (c >= 0xe000 && c <= 0xfffd))
	    {
	      switch (c)
		{
		  case '"':
		    to[j++] = '&';
		    to[j++] = 'q';
		    to[j++] = 'u';
		    to[j++] = 'o';
		    to[j++] = 't';
		    to[j++] = ';';
		    break;

		  case '\'':
		    to[j++] = '&';
		    to[j++] = 'a';
		    to[j++] = 'p';
		    to[j++] = 'o';
		    to[j++] = 's';
		    to[j++] = ';';
		    break;

		  case '&':
		    to[j++] = '&';
		    to[j++] = 'a';
		    to[j++] = 'm';
		    to[j++] = 'p';
		    to[j++] = ';';
		    break;

		  case '<':
		    to[j++] = '&';
		    to[j++] = 'l';
		    to[j++] = 't';
		    to[j++] = ';';
		    break;

		  case '>':
		    to[j++] = '&';
		    to[j++] = 'g';
		    to[j++] = 't';
		    to[j++] = ';';
		    break;

		  default:
		    if (c > 127)
		      {
			char	buf[12];
			char	*ptr = buf;

			to[j++] = '&';
			to[j++] = '#';
			sprintf(buf, "%u", c);
			while (*ptr != '\0')
			  {
			    to[j++] = *ptr++;
			  }
			to[j++] = ';';
		      }
		    else
		      {
			to[j++] = c;
		      }
		    break;
		}
	    }
	}
      str = [[NSString alloc] initWithCharacters: to length: output];
      NSZoneFree (NSDefaultMallocZone (), to);
      [str autorelease];
    }
  NSZoneFree (NSDefaultMallocZone (), from);
  return str;
}

+ (NSURL*) linkPath: (NSString*)newPath
	   relative: (NSURL*)oldURL
	      query: (NSDictionary*)fields, ...
{
  va_list		ap;
  NSMutableDictionary	*m;
  id			key;
  id			val;
  NSRange		r;

  m = [fields mutableCopy];
  va_start (ap, fields);
  while ((key = va_arg(ap, id)) != nil && (val = va_arg(ap, id)) != nil)
    {
      if (m == nil)
	{
	  m = [[NSMutableDictionary alloc] initWithCapacity: 2];
	}
      [m setObject: val forKey: key];
    }
  va_end (ap);

  /* The new path must NOT contain a query string.
   */
  r = [newPath rangeOfString: @"?"];
  if (r.length > 0)
    {
      newPath = [newPath substringToIndex: r.location];
    }

  if ([m count] > 0)
    {
      NSMutableData	*data;

      data = [[newPath dataUsingEncoding: NSUTF8StringEncoding] mutableCopy];
      [data appendBytes: "?" length: 1];
      [self encodeURLEncodedForm: m into: data];
      newPath = [NSString alloc];
      newPath = [newPath initWithData: data encoding: NSUTF8StringEncoding];
      [newPath autorelease];
      [data release];
    }
  [m release];

  if (oldURL == nil)
    {
      return [NSURL URLWithString: newPath];
    }
  else
    {
      return [NSURL URLWithString: newPath relativeToURL: oldURL];
    }
}

+ (NSData*) parameter: (NSString*)name
		   at: (NSUInteger)index
		 from: (NSDictionary*)params
{
  NSArray	*a = [params objectForKey: name];

  if (a == nil)
    {
      NSEnumerator	*e = [params keyEnumerator];
      NSString		*k;

      while ((k = [e nextObject]) != nil)
	{
	  if ([k caseInsensitiveCompare: name] == NSOrderedSame)
	    {
	      a = [params objectForKey: k];
	      break;
	    }
	}
    }
  if (index >= [a count])
    {
      return nil;
    }
  return [a objectAtIndex: index];
}

+ (NSString*) parameterString: (NSString*)name
			   at: (NSUInteger)index
			 from: (NSDictionary*)params
		      charset: (NSString*)charset
{
  NSData	*d = [self parameter: name at: index from: params];
  NSString	*s = nil;

  if (d != nil)
    {
      s = Alloc(NSStringClass);
      if (charset == nil || [charset length] == 0)
	{
	  s = [s initWithData: d encoding: NSUTF8StringEncoding];
	}
      else
	{
	  NSStringEncoding	enc;

	  enc = [GSMimeDocumentClass encodingFromCharset: charset];
	  s = [s initWithData: d encoding: enc];
	}
    }
  return AUTORELEASE(s);
}

+ (BOOL) redirectRequest: (GSMimeDocument*)request
		response: (GSMimeDocument*)response
		      to: (id)destination
{
  NSString	*s;
  NSString	*type;
  NSString	*body;

  /* If the destination is not an NSURL, take it as a string defining a
   * relative URL from the request base URL.
   */
  if (NO == [destination isKindOfClass: [NSURL class]])
    {
      s = [destination description];
      destination = [self baseURLForRequest: request];
      if (s != nil)
	{
	  destination = [NSURL URLWithString: s relativeToURL: destination];
	}
    }
  s = [destination absoluteString];

  [response setHeader: @"Location" value: s parameters: nil];
  [response setHeader: @"http"
		value: @"HTTP/1.1 302 Found"
	   parameters: nil];

  type = @"text/html";
  body = [NSString stringWithFormat: @"<a href=\"%@\">continue</a>",
    [self escapeHTML: s]];
  s = [[request headerNamed: @"accept"] value];
  if ([s length] > 0)
    {
      NSEnumerator      *e;

      /* Enumerate through all the supported types.
       */
      e = [[s componentsSeparatedByString: @","] objectEnumerator];
      while ((s = [e nextObject]) != nil)
        {
          /* Separate the type from any parameters.
           */
          s = [[[s componentsSeparatedByString: @";"] objectAtIndex: 0]
            stringByTrimmingSpaces];
          if ([s isEqualToString: @"text/html"] == YES
            || [s isEqualToString: @"text/xhtml"] == YES
            || [s isEqualToString: @"application/xhtml+xml"] == YES
            || [s isEqualToString: @"application/vnd.wap.xhtml+xml"] == YES
            || [s isEqualToString: @"text/vnd.wap.wml"] == YES)
            {
              type = s;
	      break;
            }
        }
    }
  [response setContent: body type: type];
  return YES;
}

- (BOOL) accessRequest: (GSMimeDocument*)request
	      response: (GSMimeDocument*)response
{
  NSDictionary		*conf = [_defs dictionaryForKey: @"WebServerAccess"];
  NSString		*path = [[request headerNamed: @"x-http-path"] value];
  NSDictionary		*access = nil;
  NSString		*stored = nil;
  NSString		*username;
  NSString		*password;

  while (access == nil)
    {
      access = [conf objectForKey: path];
      if ([access isKindOfClass: NSDictionaryClass] == NO)
	{
	  NSRange	r;

	  access = nil;
	  r = [path rangeOfString: @"/" options: NSBackwardsSearch];
	  if (r.length > 0)
	    {
	      path = [path substringToIndex: r.location];
	    }
	  else
	    {
	      return YES;	// No access dictionary - permit access
	    }
	}
    }

  username = [[request headerNamed: @"x-http-username"] value];
  password = [[request headerNamed: @"x-http-password"] value];
  if ([access objectForKey: @"Users"] != nil)
    {
      NSDictionary	*users = [access objectForKey: @"Users"];

      stored = [users objectForKey: username];
    }

  if (username == nil || password == nil || [password isEqual: stored] == NO)
    {
      NSString	*realm = [access objectForKey: @"Realm"];
      NSString	*auth;

      auth = [NSStringClass stringWithFormat: @"Basic realm=\"%@\"", realm];

      /*
       * Return status code 401 (Aunauthorised)
       */
      [response setHeader: @"http"
		    value: @"HTTP/1.1 401 Unauthorised"
	       parameters: nil];
      [response setHeader: @"WWW-authenticate"
		    value: auth
	       parameters: nil];

      [response setContent:
@"<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\">\n"
@"<html><head><title>401 Authorization Required</title></head><body>\n"
@"<h1>Authorization Required</h1>\n"
@"<p>This server could not verify that you "
@"are authorized to access the resource "
@"requested.  Either you supplied the wrong "
@"credentials (e.g., bad password), or your "
@"browser doesn't understand how to supply "
@"the credentials required.</p>\n"
@"</body></html>\n"
	type: @"text/html"];

      return NO;
    }
  else
    {
      return YES;	// OK to access
    }
}

- (void) completedWithResponse: (GSMimeDocument*)response
{
  static NSArray	*modes = nil;
  WebServerConnection	*connection;

  if (modes == nil)
    {
      id	objs[1];

      objs[0] = NSDefaultRunLoopMode;
      modes = [Alloc(NSArrayClass) initWithObjects: objs count: 1];
    }
  connection = [(WebServerResponse*)response webServerConnection];
  [_lock lock];
  _processingCount--;
  [_lock unlock];
  [_pool scheduleSelector: @selector(respond)
	       onReceiver: connection
	       withObject: nil];
}

- (void) dealloc
{
  [self setPort: nil secure: nil];
  DESTROY(_nc);
  DESTROY(_defs);
  DESTROY(_root);
  DESTROY(_conf);
  DESTROY(_perHost);
  DESTROY(_lock);
  DESTROY(_connections);
  DESTROY(_xCountRequests);
  DESTROY(_xCountConnections);
  DESTROY(_xCountConnectedHosts);
  [super dealloc];
}

- (NSUInteger) decodeURLEncodedForm: (NSData*)data
			     into: (NSMutableDictionary*)dict
{
  return [[self class] decodeURLEncodedForm: data into: dict];
}

- (NSUInteger) encodeURLEncodedForm: (NSDictionary*)dict
			       into: (NSMutableData*)data
{
  return [[self class] encodeURLEncodedForm: dict into: data];
}

- (NSString*) escapeHTML: (NSString*)str
{
  return [[self class] escapeHTML: str];
}

- (NSString*) description
{
  NSString	*result;

  [_lock lock];
  result = [NSStringClass stringWithFormat:
    @"%@ on %@(%@), %u of %u connections active,"
    @" %u ended, %u requests, listening: %@\nThread pool %@",
    [super description], _port, ([self isSecure] ? @"https" : @"http"),
    [_connections count],
    _maxConnections, _handled, _requests, _accepting == YES ? @"yes" : @"no",
    _pool];
  [_lock unlock];
  return result;
}

- (id) init
{
  _nc = [[NSNotificationCenter defaultCenter] retain];
  _lock =  [NSLock new];
  _pool = [GSThreadPool new];
  [_pool setThreads: 0];
  _defs = [[NSUserDefaults standardUserDefaults] retain];
  _quiet = [[_defs arrayForKey: @"WebServerQuiet"] copy];
  _hosts = [[_defs arrayForKey: @"WebServerHosts"] copy];
  _conf = [WebServerConfig new];
  _conf->reverse = [_defs boolForKey: @"ReverseHostLookup"];
  _conf->maxConnectionRequests = 100;
  _conf->maxConnectionDuration = 10.0;
  _conf->maxBodySize = 4*1024*1024;
  _conf->maxRequestSize = 8*1024;
  _conf->connectionTimeout = 30.0;
  _maxPerHost = 32;
  _maxConnections = 128;
  _substitutionLimit = 4;
  _connections = [NSMutableSet new];
  _perHost = [NSCountedSet new];
  _ioThread = [NSThread mainThread];
  _xCountRequests = [[WebServerHeader alloc]
    initWithType: WSHCountRequests andObject: self];
  _xCountConnections = [[WebServerHeader alloc]
    initWithType: WSHCountConnections andObject: self];
  _xCountConnectedHosts = [[WebServerHeader alloc]
    initWithType: WSHCountConnectedHosts andObject: self];

  return self;
}

- (BOOL) isSecure
{
  if (_sslConfig == nil)
    {
      return NO;
    }
  return YES;
}

- (BOOL) produceResponse: (GSMimeDocument*)aResponse
	  fromStaticPage: (NSString*)aPath
		   using: (NSDictionary*)map
{
  CREATE_AUTORELEASE_POOL(arp);
  NSString	*path = (_root == nil) ? (id)@"" : (id)_root;
  NSString	*ext = [aPath pathExtension];
  id		data = nil;
  NSString	*type;
  NSString	*str;
  NSFileManager	*mgr;
  BOOL		string = NO;
  BOOL		result = YES;

  if (map == nil)
    {
      static NSDictionary	*defaultMap = nil;

      if (defaultMap == nil)
	{
	  defaultMap = [Alloc(NSDictionaryClass) initWithObjectsAndKeys:
	    @"image/gif", @"gif",
	    @"image/png", @"png",
	    @"image/jpeg", @"jpeg",
	    @"image/jpeg", @"jpg",
	    @"text/html", @"html",
	    @"text/plain", @"txt",
	    @"text/xml", @"xml",
	    nil];
	}
      map = defaultMap;
    }

  type = [map objectForKey: ext]; 
  if (type == nil)
    {
      type = [map objectForKey: [ext lowercaseString]]; 
    }
  if (type == nil)
    {
      type = @"application/octet-stream";
    }
  string = [type hasPrefix: @"text/"];

  path = [path stringByAppendingString: @"/"];
  str = [path stringByStandardizingPath];
  path = [path stringByAppendingPathComponent: aPath];
  path = [path stringByStandardizingPath];
  mgr = [NSFileManager defaultManager];
  if ([path hasPrefix: str] == NO)
    {
      [self _log: @"Illegal static page '%@' ('%@')", aPath, path];
      result = NO;
    }
  else if ([mgr isReadableFileAtPath: path] == NO)
    {
      [self _log: @"Can't read static page '%@' ('%@')", aPath, path];
      result = NO;
    }
  else if (string == YES
    && (data = [NSStringClass stringWithContentsOfFile: path]) == nil)
    {
      [self _log: @"Failed to load string '%@' ('%@')", aPath, path];
      result = NO;
    }
  else if (string == NO
    && (data = [NSDataClass dataWithContentsOfFile: path]) == nil)
    {
      [self _log: @"Failed to load data '%@' ('%@')", aPath, path];
      result = NO;
    }
  else
    {
      [aResponse setContent: data type: type name: nil];
    }
  DESTROY(arp);
  return result;
}

- (BOOL) produceResponse: (GSMimeDocument*)aResponse
	    fromTemplate: (NSString*)aPath
		   using: (NSDictionary*)map
{
  CREATE_AUTORELEASE_POOL(arp);
  NSString	*path = (_root == nil) ? (id)@"" : (id)_root;
  NSString	*str;
  NSFileManager	*mgr;
  BOOL		result;

  path = [path stringByAppendingString: @"/"];
  str = [path stringByStandardizingPath];
  path = [path stringByAppendingPathComponent: aPath];
  path = [path stringByStandardizingPath];
  mgr = [NSFileManager defaultManager];
  if ([path hasPrefix: str] == NO)
    {
      [self _log: @"Illegal template '%@' ('%@')", aPath, path];
      result = NO;
    }
  else if ([mgr isReadableFileAtPath: path] == NO)
    {
      [self _log: @"Can't read template '%@' ('%@')", aPath, path];
      result = NO;
    }
  else if ((str = [NSStringClass stringWithContentsOfFile: path]) == nil)
    {
      [self _log: @"Failed to load template '%@' ('%@')", aPath, path];
      result = NO;
    }
  else
    {
      NSMutableString	*m;

      m = [Alloc(NSMutableStringClass) initWithCapacity: [str length]];
      result = [self substituteFrom: str
			      using: map
			       into: m
			      depth: 0];
      if (result == YES)
	{
	  [aResponse setContent: m type: @"text/html" name: nil];
	  [[aResponse headerNamed: @"content-type"] setParameter: @"utf-8"
							  forKey: @"charset"];
	}
      RELEASE(m);
    }
  DESTROY(arp);
  return result;
}

- (NSMutableDictionary*) parameters: (GSMimeDocument*)request
{
  NSMutableDictionary	*params;
  NSString		*str = [[request headerNamed: @"x-http-query"] value];
  NSData		*data;

  params = [NSMutableDictionaryClass dictionaryWithCapacity: 32];
  if ([str length] > 0)
    {
      data = [str dataUsingEncoding: NSASCIIStringEncoding];
      [self decodeURLEncodedForm: data into: params];
    }

  str = [[request headerNamed: @"content-type"] value];
  if ([str isEqualToString: @"application/x-www-form-urlencoded"] == YES)
    {
      data = [request convertToData];
      [self decodeURLEncodedForm: data into: params];
    }
  else if ([str isEqualToString: @"multipart/form-data"] == YES)
    {
      NSArray	*contents = [request content];
      NSUInteger	count = [contents count];
      NSUInteger	i;

      for (i = 0; i < count; i++)
	{
	  GSMimeDocument	*doc = [contents objectAtIndex: i];
	  GSMimeHeader		*hdr = [doc headerNamed: @"content-type"];
	  NSString		*k = [hdr parameterForKey: @"name"];

	  if (k == nil)
	    {
	      hdr = [doc headerNamed: @"content-disposition"];
	      k = [hdr parameterForKey: @"name"];
	    }
	  if (k != nil)
	    {
	      NSMutableArray	*a;

	      a = [params objectForKey: k];
	      if (a == nil)
		{
		  a = [Alloc(NSMutableArrayClass) initWithCapacity: 1];
		  [params setObject: a forKey: k];
		  RELEASE(a);
		}
	      [a addObject: [doc convertToData]];
	    }
	}
    }

  return params;
}

- (NSData*) parameter: (NSString*)name
		   at: (NSUInteger)index
		 from: (NSDictionary*)params
{
  return [[self class] parameter: name at: index from: params];
}

- (NSData*) parameter: (NSString*)name from: (NSDictionary*)params
{
  return [self parameter: name at: 0 from: params];
}

- (NSString*) parameterString: (NSString*)name
			   at: (NSUInteger)index
			 from: (NSDictionary*)params
{
  return [self parameterString: name at: index from: params charset: nil];
}

- (NSString*) parameterString: (NSString*)name
			   at: (NSUInteger)index
			 from: (NSDictionary*)params
		      charset: (NSString*)charset
{
  return [[self class] parameterString: name
				    at: index
				  from: params
			       charset: charset];
}

- (NSString*) parameterString: (NSString*)name from: (NSDictionary*)params
{
  return [self parameterString: name at: 0 from: params charset: nil];
}

- (NSString*) parameterString: (NSString*)name
			 from: (NSDictionary*)params
		      charset: (NSString*)charset
{
  return [self parameterString: name at: 0 from: params charset: charset];
}

- (void) setDelegate: (id)anObject
{
  _delegate = anObject;
}

- (void) setDurationLogging: (BOOL)aFlag
{
  if (aFlag != _conf->durations)
    {
      WebServerConfig	*c = [_conf copy];
  
      c->durations = aFlag;
      [_conf release];
      _conf = c;
    }
}

- (void) setMaxBodySize: (NSUInteger)max
{
  if (max != _conf->maxBodySize)
    {
      WebServerConfig	*c = [_conf copy];
  
      c->maxBodySize = max;
      [_conf release];
      _conf = c;
    }
}

- (void) setMaxConnectionDuration: (NSTimeInterval)max
{
  if (max != _conf->maxConnectionDuration)
    {
      WebServerConfig	*c = [_conf copy];
  
      c->maxConnectionDuration = max;
      [_conf release];
      _conf = c;
    }
}

- (void) setMaxConnectionRequests: (NSUInteger)max
{
  if (max != _conf->maxConnectionRequests)
    {
      WebServerConfig	*c = [_conf copy];
  
      c->maxConnectionRequests = max;
      [_conf release];
      _conf = c;
    }
}

- (void) setMaxConnections: (NSUInteger)max
{
  if (0 == max || max > MAXCONNECTIONS)
    {
      max = MAXCONNECTIONS;
    }
  _maxConnections = max;
  if (_maxPerHost > max)
    {
      _maxPerHost = max;
    }
  [_pool setOperations: max];
}

- (void) setMaxConnectionsPerHost: (NSUInteger)max
{
  if (0 == max || max > MAXCONNECTIONS)
    {
      max = MAXCONNECTIONS;
    }
  if (max > _maxConnections)
    {
      max = _maxConnections;
    }
  _maxPerHost = max;
  [_pool setOperations: max];
}

- (void) setMaxConnectionsReject: (BOOL)reject
{
  _reject = (reject == YES) ? 1 : 0;
}

- (void) setMaxRequestSize: (NSUInteger)max
{
  if (max != _conf->maxRequestSize)
    {
      WebServerConfig	*c = [_conf copy];
  
      c->maxRequestSize = max;
      [_conf release];
      _conf = c;
    }
}

- (BOOL) setPort: (NSString*)aPort secure: (NSDictionary*)secure
{
  BOOL	ok = YES;
  BOOL	update = NO;

  if (aPort == nil || [aPort isEqual: _port] == NO)
    {
      update = YES;
    }
  if ((secure == nil && _sslConfig != nil)
    || (secure != nil && [secure isEqual: _sslConfig] == NO))
    {
      update = YES;
    }

  if (update == YES)
    {
      ASSIGNCOPY(_sslConfig, secure);
      if (_listener != nil)
	{
	  [_nc removeObserver: self
			 name: NSFileHandleConnectionAcceptedNotification
		       object: _listener];
	  DESTROY(_listener);
	}
      _accepting = NO;	// No longer listening for connections.
      DESTROY(_port);
      if (aPort != nil)
	{
	  _port = [aPort copy];
	  if (_sslConfig != nil)
	    {
	      _listener = [[NSFileHandle sslClass]
		fileHandleAsServerAtAddress: nil
		service: _port
		protocol: @"tcp"];
	    }
	  else
	    {
	      _listener = [NSFileHandle fileHandleAsServerAtAddress: nil
							    service: _port
							   protocol: @"tcp"];
	    }

	  if (_listener == nil)
	    {
	      [self _alert: @"Failed to listen on port %@", _port];
	      DESTROY(_port);
	      ok = NO;
	    }
	  else
	    {
	      RETAIN(_listener);
	      [_nc addObserver: self
		      selector: @selector(_didConnect:)
			  name: NSFileHandleConnectionAcceptedNotification
			object: _listener];
	      [self _listen];
	    }
	}
    }
  return ok;
}

- (void) setRoot: (NSString*)aPath
{
  ASSIGN(_root, aPath);
}

- (void) setSecureProxy: (BOOL)aFlag
{
  if (aFlag != _conf->secureProxy)
    {
      WebServerConfig	*c = [_conf copy];
  
      c->secureProxy = aFlag;
      [_conf release];
      _conf = c;
    }
}

- (void) setConnectionTimeout: (NSTimeInterval)aDelay
{
  if (_conf->connectionTimeout != aDelay)
    {
      WebServerConfig	*c = [_conf copy];

      c->connectionTimeout = aDelay;
      [_conf release];
      _conf = c;
    }
}

- (void) setSubstitutionLimit: (NSUInteger)depth
{
  _substitutionLimit = depth;
}

- (void) _ioThread
{
  _ioThread = [NSThread currentThread];
  _ioTimer = [NSTimer scheduledTimerWithTimeInterval: 10000000.0
    target: self
    selector: @selector(timeout:)
    userInfo: 0
    repeats: NO];
  [[NSRunLoop currentRunLoop] run];
}

- (void) setThreads: (NSUInteger)threads
{
  if (threads != [_pool maxThreads])
    {
      if (threads > 0)
	{
	  [_pool setOperations: _maxConnections];
          [NSThread detachNewThreadSelector: @selector(_ioThread)  
				   toTarget: self
				 withObject: nil];
	}
      else
	{
	  [_pool setOperations: 0];
	  [_ioTimer invalidate];
	  _ioTimer = nil;
	  [_ioThread release];
	  _ioThread = [NSThread mainThread];
	}
      [_pool setThreads: threads];
    }
}

- (void) setThreadProcessing: (BOOL)aFlag
{
  _threadProcessing = aFlag;
}

- (void) setUserInfo: (NSObject*)info forRequest: (GSMimeDocument*)request
{
  WebServerHeader	*h;

  h = [WebServerHeaderClass alloc];
  h = [h initWithName: @"mime-version"
		    value: @"1.0"
	       parameters: nil];
  [h setWebServerExtra: info];
  [request addHeader: h];
  [h release];
}

- (void) setVerbose: (BOOL)aFlag
{
  if (aFlag != _conf->verbose)
    {
      WebServerConfig	*c = [_conf copy];
  
      c->verbose = aFlag;
      if (YES == aFlag)
	{
	  c->durations = YES;
	}
      [_conf release];
      _conf = c;
    }
}

- (BOOL) substituteFrom: (NSString*)aTemplate
                  using: (NSDictionary*)map
		   into: (NSMutableString*)result
		  depth: (NSUInteger)depth
{
  NSUInteger	length;
  NSUInteger	pos = 0;
  NSRange	r;

  if (depth > _substitutionLimit)
    {
      [self _alert: @"Substitution exceeded limit (%u)", _substitutionLimit];
      return NO;
    }

  length = [aTemplate length];
  r = NSMakeRange(pos, length);
  r = [aTemplate rangeOfString: @"<!--"
		       options: NSLiteralSearch
			 range: r];
  while (r.length > 0)
    {
      NSUInteger	start = r.location;

      if (start > pos)
	{
	  r = NSMakeRange(pos, r.location - pos);
	  [result appendString: [aTemplate substringWithRange: r]];
	}
      pos = start;
      r = NSMakeRange(start + 4, length - start - 4);
      r = [aTemplate rangeOfString: @"-->"
			   options: NSLiteralSearch
			     range: r];
      if (r.length > 0)
	{
	  NSUInteger	end = NSMaxRange(r);
	  NSString	*subFrom;
	  NSString	*subTo;

	  r = NSMakeRange(start + 4, r.location - start - 4);
	  subFrom = [aTemplate substringWithRange: r];
	  subTo = [map objectForKey: subFrom];
	  if (subTo == nil)
	    {
	      [result appendString: @"<!--"];
	      pos += 4;
	    }
	  else
	    {
	      /*
	       * Unless the value substituted in is a comment,
	       * perform recursive substitution.
	       */
	      if ([subTo hasPrefix: @"<!--"] == NO)
		{
		  BOOL	v;

		  v = [self substituteFrom: subTo
				     using: map
				      into: result
				     depth: depth + 1];
		  if (v == NO)
		    {
		      return NO;
		    }
		}
	      else
		{
		  [result appendString: subTo];
		}
	      pos = end;
	    }
	}
      else
	{
	  [result appendString: @"<!--"];
	  pos += 4;
	}
      r = NSMakeRange(pos, length - pos);
      r = [aTemplate rangeOfString: @"<!--"
			   options: NSLiteralSearch
			     range: r];
    }

  if (pos < length)
    {
      r = NSMakeRange(pos, length - pos);
      [result appendString: [aTemplate substringWithRange: r]];
    }
  return YES;
}

- (NSObject*) userInfoForRequest: (GSMimeDocument*)request
{
  id	o = [request headerNamed: @"mime-version"];

  if (object_getClass(o) == WebServerHeaderClass)
    {
      return [o webServerExtra];
    }
  return nil;
}

@end

@implementation	WebServer (Private)

- (void) _alert: (NSString*)fmt, ...
{
  va_list	args;

  va_start(args, fmt);
  if ([_delegate respondsToSelector: @selector(webAlert:for:)] == YES)
    {
      NSString	*s;

      s = [NSStringClass stringWithFormat: fmt arguments: args];
      [_delegate webAlert: s for: self];
    }
  else
    {
      NSLogv(fmt, args);
    }
  va_end(args);
}

- (void) _audit: (WebServerConnection*)connection
{
  if ([_delegate respondsToSelector: @selector(webAudit:for:)] == YES)
    {
      [_delegate webAudit: [connection audit] for: self];
    }
  else
    {
      fprintf(stderr, "%s\r\n", [[connection audit] UTF8String]);
    } 
}

- (void) _didConnect: (NSNotification*)notification
{
  NSDictionary		*userInfo = [notification userInfo];
  NSFileHandle		*hdl;

  _accepting = NO;
  _ticked = [NSDateClass timeIntervalSinceReferenceDate];
  hdl = [userInfo objectForKey: NSFileHandleNotificationFileHandleItem];
  if (hdl == nil)
    {
      /* Try to allow more connections to be accepted.
       */
      [self _listen];
      [NSException raise: NSInternalInconsistencyException
		  format: @"[%@ -%@] missing handle",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  else
    {
      WebServerConnection	*connection;
      NSString			*address;
      NSString			*refusal;
      BOOL			quiet;
      BOOL			ssl;

      [_lock lock];
      if (nil == _sslConfig)
	{
	  ssl = NO;
	}
      else
	{
	  NSString	*address = [hdl socketLocalAddress];
	  NSDictionary	*primary = [_sslConfig objectForKey: address];
	  NSString	*certificateFile;
	  NSString	*keyFile;
	  NSString	*password;

	  certificateFile = [primary objectForKey: @"CertificateFile"];
	  if (certificateFile == nil)
	    {
	      certificateFile = [_sslConfig objectForKey: @"CertificateFile"];
	    }
	  keyFile = [primary objectForKey: @"KeyFile"];
	  if (keyFile == nil)
	    {
	      keyFile = [_sslConfig objectForKey: @"KeyFile"];
	    }
	  password = [primary objectForKey: @"Password"];
	  if (password == nil)
	    {
	      password = [_sslConfig objectForKey: @"Password"];
	    }
	  [hdl sslSetCertificate: certificateFile
		      privateKey: keyFile
		       PEMpasswd: password];
	  ssl = YES;
	}

      address = [hdl socketAddress];
      if (nil == address)
	{
	  refusal = @"HTTP/1.0 403 Unable to determine client host address";
	}
      else if (_hosts != nil && [_hosts containsObject: address] == NO)
	{
	  refusal = @"HTTP/1.0 403 Not a permitted client host";
	}
      else if (_maxConnections > 0
        && [_connections count] >= _maxConnections)
	{
	  refusal =  @"HTTP/1.0 503 Too many existing connections";
	}
      else if (_maxPerHost > 0
	&& [_perHost countForObject: address] >= _maxPerHost)
	{
	  refusal = @"HTTP/1.0 503 Too many existing connections from host";
	}
      else
	{
	  refusal = nil;
	}
      quiet = [_quiet containsObject: address];

      connection = [WebServerConnection alloc]; 
      connection = [connection initWithHandle: hdl
					  for: self
				      address: address
				       config: _conf
					quiet: quiet
					  ssl: ssl
				      refusal: refusal];
      [connection setTicked: _ticked];
      [connection setConnectionStart: _ticked];

      [_connections addObject: connection];
      [connection release];	// Retained in _connections map
      [_perHost addObject: address];
      [_lock unlock];

      /* Ensure we always have an 'accept' in progress unless we are already
       * handling the maximum number of connections.
       */
      [self _listen];
      [_pool scheduleSelector: @selector(start)
		   onReceiver: connection
		   withObject: nil];
    }
}

- (void) _endConnect: (WebServerConnection*)connection
{
  /* The connection must actually be closed in the same thread that
   * it uses for I/O or we will leave a reference to it in the
   * runloop.
   */
  [self performSelector: @selector(_removeConnection:)
	       onThread: _ioThread
	     withObject: connection
	  waitUntilDone: NO];
}

- (void) _removeConnection: (WebServerConnection*)connection
{
  [connection retain];
  [_lock lock];
  if (NO == [connection quiet])
    {
      [self _audit: connection];
      _handled++;
    }
  [_perHost removeObject: [connection address]];
  [_connections removeObject: connection];
  [_lock unlock];
  [connection end];
  [connection release];
  [self _listen];
}

- (void) _listen
{
  [_lock lock];
  if (_accepting == NO && (_maxConnections == 0
    || [_connections count] < (_maxConnections + _reject)))
    {
      _accepting = YES;
      [_lock unlock];
      [_listener performSelector:
	@selector(acceptConnectionInBackgroundAndNotify)
	onThread: _ioThread
	withObject: nil
	waitUntilDone: NO];
    }
  else
    {
      [_lock unlock];
    }
}

- (void) _log: (NSString*)fmt, ...
{
  va_list	args;

  va_start(args, fmt);
  if ([_delegate respondsToSelector: @selector(webLog:for:)] == YES)
    {
      NSString	*s;

      s = [NSStringClass stringWithFormat: fmt arguments: args];
      [_delegate webLog: s for: self];
    }
  va_end(args);
}

- (void) _process1: (WebServerConnection*)connection
{
  NSFileHandle		*h;
  GSMimeDocument	*request;
  WebServerResponse	*response;
  NSString		*str;
  NSString		*con;
  BOOL			processed = YES;

  [_lock lock];
  _processingCount++;
  [_lock unlock];

  request = [connection request];
  response = [connection response];
  [connection setExcess: [[connection parser] excess]];

  /*
   * Provide information and update the shared process statistics.
   */
  [request addHeader: _xCountRequests];
  [request addHeader: _xCountConnections];
  [request addHeader: _xCountConnectedHosts];
  h = [connection handle];
  str = [h socketAddress];
  str = [NSStringClass stringWithFormat: @"%u", [_perHost countForObject: str]];
  [request setHeader: @"x-count-host-connections"
	       value: str
	  parameters: nil];

  [connection setProcessing: YES];
  [connection setAgent: [[request headerNamed: @"user-agent"] value]];

  /*
   * If the client specified that the connection should close, we don't
   * keep it open.
   */
  con = [[request headerNamed: @"connection"] value]; 
  if (con != nil)
    {
      if ([con caseInsensitiveCompare: @"keep-alive"] == NSOrderedSame)
	{
	  [connection setShouldClose: NO];	// Persistent (even in HTTP 1.0)
	  [response setHeader: @"Connection"
		        value: @"Keep-Alive"
		   parameters: nil];
	}
      else if ([con caseInsensitiveCompare: @"close"] == NSOrderedSame)
	{
	  [connection setShouldClose: YES];	// Not persistent.
	}
    }

  /*
   * Provide more information about the connection.
   */
  [request setHeader: @"x-local-address"
	       value: [h socketLocalAddress]
	  parameters: nil];
  [request setHeader: @"x-local-port"
	       value: [h socketLocalService]
	  parameters: nil];
  [request setHeader: @"x-remote-address"
	       value: [h socketAddress]
	  parameters: nil];
  [request setHeader: @"x-remote-port"
	       value: [h socketService]
	  parameters: nil];

  str = [[request headerNamed: @"authorization"] value];
  if ([str length] > 6 && [[str substringToIndex: 6] caseInsensitiveCompare:
    @"Basic "] == NSOrderedSame)
    {
      str = [[str substringFromIndex: 6] stringByTrimmingSpaces];
      str = [GSMimeDocument decodeBase64String: str];
      if ([str length] > 0)
	{
	  NSRange	r = [str rangeOfString: @":"];

	  if (r.length > 0)
	    {
	      NSString	*user = [str substringToIndex: r.location];

	      [connection setUser: user];
	      [request setHeader: @"x-http-username"
			   value: user
		      parameters: nil];
	      [request setHeader: @"x-http-password"
			   value: [str substringFromIndex: NSMaxRange(r)]
		      parameters: nil];
	    }
	}
    }

  [response setContent: [NSDataClass data] type: @"text/plain" name: nil];

  if ([_quiet containsObject: [connection address]] == NO)
    {
      [_lock lock];
      _requests++;
      [_lock unlock];
      if (YES == _conf->verbose)
	{
	  [self _log: @"Request %@ - %@", connection, request];
	}
    }

  if (YES == _threadProcessing)
    {
      [_pool scheduleSelector: @selector(_process2:)
		   onReceiver: self
		   withObject: connection];
    }
  else
    {
      [self performSelectorOnMainThread: @selector(_process2:)
			     withObject: connection
			  waitUntilDone: NO];
    }
}

- (void) _process2: (WebServerConnection*)connection
{
  GSMimeDocument	*request;
  WebServerResponse	*response;
  BOOL			processed = YES;

  request = [connection request];
  response = [connection response];

  NS_DURING
    {
      [connection setTicked: _ticked];
      if ([self accessRequest: request response: response] == YES)
	{
	  processed = [_delegate processRequest: request
				       response: response
					    for: self];
	}
      _ticked = [NSDateClass timeIntervalSinceReferenceDate];
      [connection setTicked: _ticked];
    }
  NS_HANDLER
    {
      [self _alert: @"Exception %@, processing %@", localException, request];
      [response setHeader: @"http"
		    value: @"HTTP/1.0 500 Internal Server Error"
	       parameters: nil];
    }
  NS_ENDHANDLER

  if (processed == YES)
    {
      [self completedWithResponse: response];
    }
}

- (void) _runConnection: (WebServerConnection*)connection
{
  NSAutoreleasePool	*pool = [NSAutoreleasePool new];
  NSRunLoop		*loop = [NSRunLoop currentRunLoop];
  NSDate		*when = [NSDate distantFuture];

  [connection start];
  while (NO == [connection ended])
    {
      if (NO == [loop runMode: NSDefaultRunLoopMode beforeDate: when])
	{
	  if (NO == [connection ended])
	    {
	      NSLog(@"Argh -runMode:beforeDate: returned NO but connection "
		@"was not ended!");
	    }
	}
    }
  [pool release];
}

- (void) _threadReadFrom: (NSFileHandle*)handle
{
  [handle performSelector: @selector(readInBackgroundAndNotify)
                 onThread: _ioThread
               withObject: nil
            waitUntilDone: NO];
}

- (void) _threadWrite: (NSData*)data to: (NSFileHandle*)handle
{
  [handle performSelector: @selector(writeInBackgroundAndNotify:)
                 onThread: _ioThread
               withObject: data
            waitUntilDone: NO];
}

- (NSString*) _xCountRequests
{
  NSString	*str;

  [_lock lock];
  str = [NSStringClass stringWithFormat: @"%u", _processingCount];
  [_lock unlock];
  return str;
}

- (NSString*) _xCountConnections
{
  NSString	*str;

  [_lock lock];
  str = [NSStringClass stringWithFormat: @"%u", [_connections count]];
  [_lock unlock];
  return str;
}

- (NSString*) _xCountConnectedHosts
{
  NSString	*str;

  [_lock lock];
  str = [NSStringClass stringWithFormat: @"%u", [_perHost count]];
  [_lock unlock];
  return str;
}

@end

@implementation	WebServerConfig
- (id) copyWithZone: (NSZone*)z
{
  return NSCopyObject(self, 0, z);
}
@end

