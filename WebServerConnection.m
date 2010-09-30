/** 
   Copyright (C) 2010 Free Software Foundation, Inc.
   
   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date:	June 2010
   
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

   $Date: 2010-09-17 16:47:13 +0100 (Fri, 17 Sep 2010) $ $Revision: 31364 $
   */ 

#import "WebServer.h"
#import "Internal.h"
#import <Foundation/NSHost.h>
#import <Foundation/NSLock.h>

static Class NSDateClass = Nil;
static Class NSMutableDataClass = Nil;
static Class NSStringClass = Nil;
static Class WebServerResponseClass = Nil;

@implementation	WebServerResponse

- (id) copy
{
  return [self copyWithZone: NSDefaultMallocZone()];
}

- (id) copyWithZone: (NSZone*)z
{
  return [self retain];
}

- (NSUInteger) hash
{
  return ((NSUInteger)self)>>2;
}

- (BOOL) isEqual: (id)other
{
  return (other == self) ? YES : NO;
}

- (void) setWebServerConnection: (WebServerConnection*)c
{
  webServerConnection = c;
}

- (WebServerConnection*) webServerConnection
{
  return webServerConnection;
}
@end


@implementation	WebServerConnection

+ (void) initialize
{
  if ([WebServerConnection class] == self)
    {
      NSDateClass = [NSDate class];
      NSMutableDataClass = [NSMutableData class];
      NSStringClass = [NSString class];
      WebServerResponseClass = self;
    }
}

- (NSString*) address
{
  return address;
}

- (NSString*) audit
{
  NSString	*h;
  NSString	*c;
  NSString	*a;
  NSString	*r;
  NSString	*u;
  NSDate	*d;

  if (address == nil)
    {
      h = @"-";
    }
  else
    {
      h = address;	
    }

  if (command == nil)
    {
      c = @"-";
    }
  else
    {
      c = [command description];	
      if ([c rangeOfString: @"\\"].length > 0)
        {
	  c = [c stringByReplacingString: @"\\" withString: @"\\\\"];
	}
      if ([c rangeOfString: @"\""].length > 0)
        {
	  c = [c stringByReplacingString: @"\"" withString: @"\\\""];
	}
      c = [NSStringClass stringWithFormat: @"\"%@\"", c];
    }

  if (agent == nil)
    {
      a = @"-";
    }
  else
    {
      a = agent;	
      if ([a rangeOfString: @"\\"].length > 0)
        {
	  a = [a stringByReplacingString: @"\\" withString: @"\\\\"];
	}
      if ([a rangeOfString: @"\""].length > 0)
        {
	  a = [a stringByReplacingString: @"\"" withString: @"\\\""];
	}
      a = [NSStringClass stringWithFormat: @"\"%@\"", a];
    }

  if (result == nil)
    {
      r = @"-";
    }
  else
    {
      r = result;	
      if ([r rangeOfString: @"\\"].length > 0)
        {
	  r = [r stringByReplacingString: @"\\" withString: @"\\\\"];
	}
      if ([r rangeOfString: @"\""].length > 0)
        {
	  r = [r stringByReplacingString: @"\"" withString: @"\\\""];
	}
      r = [NSStringClass stringWithFormat: @"\"%@\"", r];
    }

  if (user == nil)
    {
      u = @"-";
    }
  else
    {
      u = user;	
    }

  if (requestStart == 0.0)
    {
      d = [NSDateClass date];
    }
  else
    {
      d = [NSDateClass dateWithTimeIntervalSinceReferenceDate: requestStart];
    }
  return [NSStringClass stringWithFormat: @"%@ - %@ [%@] %@ %@ %@",
    h, u, d, c, a, r];
}

- (void) dealloc
{
  [handle closeFile];
  DESTROY(ioThread);
  DESTROY(handle);
  DESTROY(excess);
  DESTROY(address);
  DESTROY(buffer);
  DESTROY(parser);
  DESTROY(command);
  DESTROY(agent);
  DESTROY(result);
  DESTROY(response);
  DESTROY(conf);
  DESTROY(nc);
  [super dealloc];
}

- (NSString*) description
{
  return [NSStringClass stringWithFormat: @"WebServerConnection: %08x [%@] ",
    [self identity], [self address]];
}

/* Must be called on the IO thread.
 */
- (void) end
{
  if ([NSThread currentThread] != ioThread->thread)
    {
      NSLog(@"Argh ... -end called on wrong thread");
      [self performSelector: @selector(end)
		   onThread: ioThread->thread
		 withObject: nil
	      waitUntilDone: YES];
    }
  else
    {
      NSFileHandle	*h;

      [nc removeObserver: self
		    name: NSFileHandleReadCompletionNotification
		  object: handle];
      [nc removeObserver: self
		    name: GSFileHandleWriteCompletionNotification
		  object: handle];
      h = handle;
      handle = nil;
      [h closeFile];
      [h release];

      ticked = [NSDateClass timeIntervalSinceReferenceDate];
      if (NO == quiet)
	{
	  NSTimeInterval	r = [self requestDuration: ticked];

	  if (r > 0.0)
	    {
	      [self setRequestEnd: ticked];
	      if (YES == conf->durations)
		{
		  [server _log: @"%@ end of request (duration %g)", self, r];
		}
	    }
	  if (YES == conf->verbose)
	    {
	      NSTimeInterval	s = [self connectionDuration: ticked];

	      [server _log: @"%@ disconnect (duration %g)", self, s];
	    }
	  [server _audit: self];
	}
      /* Remove from the linked list we are in (if any).
       */
      [ioThread->threadLock lock];
      if (owner != nil)
	{
	  GSLinkedListRemove(self, owner);
	}
      [ioThread->threadLock unlock];
      [server _endConnect: self];
    }
}

- (BOOL) ended
{
  if (nil == handle)
    {
      return YES;
    }
  return NO;
}

- (NSData*) excess
{
  return excess;
}

- (NSFileHandle*) handle
{
  return handle;
}

- (BOOL) hasReset
{
  return hasReset;
}

- (NSUInteger) identity
{
  return identity;
}

- (id) initWithHandle: (NSFileHandle*)hdl
	     onThread: (IOThread*)t
		  for: (WebServer*)svr
	      address: (NSString*)adr
	       config: (WebServerConfig*)c
		quiet: (BOOL)q
		  ssl: (BOOL)s
	      refusal: (NSString*)r
{
  static NSUInteger	connectionIdentity = 0;

  if ((self = [super init]) != nil)
    {
      nc = [[NSNotificationCenter defaultCenter] retain];
      server = svr;
      identity = ++connectionIdentity;
      requestStart = 0.0;
      duration = 0.0;
      requests = 0;
      ASSIGN(handle, hdl);
      address = [adr copy];
      conf = [c retain];
      quiet = q;
      ssl = s;
      result = [r copy];
      ioThread = [t retain];
      [ioThread->threadLock lock];
      if (YES == ssl)
	{
	  GSLinkedListInsertAfter(self, t->handshakes, t->handshakes->tail);
	}
      else
	{
	  GSLinkedListInsertAfter(self, t->readwrites, t->readwrites->tail);
	}
      [ioThread->threadLock unlock];
    }
  return self;
}

- (IOThread*) ioThread
{
  return ioThread;
}

- (NSUInteger) moreBytes: (NSUInteger)count
{
  byteCount += count;
  return byteCount;
}

- (GSMimeParser*) parser
{
  return parser;
}

- (BOOL) processing
{
  return  owner == ioThread->processing ? YES : NO;
}

- (BOOL) quiet
{
  return quiet;
}

- (GSMimeDocument*) request
{
  return [parser mimeDocument];
}

- (NSTimeInterval) requestDuration: (NSTimeInterval)now
{
  if (requestStart > 0.0)
    {
      return now - requestStart;
    }
  return 0.0;
}

- (NSUInteger) requests
{
  return requests;
}

- (void) reset
{
  hasReset = YES;
  simple = NO;
  DESTROY(command);
  [response setWebServerConnection: nil];
  DESTROY(response);
  DESTROY(agent);
  DESTROY(result);
  byteCount = 0;
  DESTROY(buffer);
  buffer = [[NSMutableDataClass alloc] initWithCapacity: 1024];
  [self setRequestStart: 0.0];
  [self setParser: nil];
  [self setProcessing: NO];
}

- (void) respond
{
  NSData	*data;

  ticked = [NSDateClass timeIntervalSinceReferenceDate];
  [self setProcessing: NO];

  [response setHeader: @"content-transfer-encoding"
		value: @"binary"
	   parameters: nil];

  if (YES == simple)
    {
      /*
       * If we had a 'simple' request with no HTTP version, we must respond
       * with a 'simple' response ... just the raw data with no headers.
       */
      data = [response convertToData];
      [self setResult: @""];
    } 
  else
    {
      NSMutableData	*out;
      NSMutableData	*raw;
      uint8_t		*buf;
      NSUInteger	len;
      NSUInteger	pos;
      NSUInteger	contentLength;
      NSEnumerator	*enumerator;
      GSMimeHeader	*hdr;
      NSString		*str;

      raw = [response rawMimeData];
      buf = [raw mutableBytes];
      len = [raw length];

      for (pos = 4; pos < len; pos++)
	{
	  if (strncmp((char*)&buf[pos-4], "\r\n\r\n", 4) == 0)
	    {
	      break;
	    }
	}
      contentLength = len - pos;
      pos -= 2;
      [raw replaceBytesInRange: NSMakeRange(0, pos) withBytes: 0 length: 0];

      out = [NSMutableDataClass dataWithCapacity: len + 1024];
      [response deleteHeaderNamed: @"mime-version"];
      [response deleteHeaderNamed: @"content-length"];
      [response deleteHeaderNamed: @"content-encoding"];
      [response deleteHeaderNamed: @"content-transfer-encoding"];
      if (contentLength == 0)
	{
	  [response deleteHeaderNamed: @"content-type"];
	}
      str = [NSStringClass stringWithFormat: @"%u", contentLength];
      [response setHeader: @"content-length" value: str parameters: nil];

      hdr = [response headerNamed: @"http"];
      if (hdr == nil)
	{
	  const char	*s;

	  if (contentLength == 0)
	    {
	      s = "HTTP/1.1 204 No Content\r\n";
	      [self setResult: @"HTTP/1.1 204 No Content"];
	    }
	  else
	    {
	      s = "HTTP/1.1 200 Success\r\n";
	      [self setResult: @"HTTP/1.1 200 Success"];
	    }
	  [out appendBytes: s length: strlen(s)];
	}
      else
	{
	  NSString	*s = [[hdr value] stringByTrimmingSpaces];

	  [self setResult: s];
	  s = [s stringByAppendingString: @"\r\n"];
	  [out appendData: [s dataUsingEncoding: NSASCIIStringEncoding]];
	  [response deleteHeader: hdr];
	  /*
	   * If the http version has been set to be an old one,
	   * we must be prepared to close the connection at once
	   * unless connection keep-alive has been set.
	   */
	  if ([s hasPrefix: @"HTTP/"] == NO)
	    {
	      [self setShouldClose: YES];
	    }
	  else if ([[s substringFromIndex: 5] floatValue] < 1.1) 
	    {
	      s = [[response headerNamed: @"connection"] value]; 
	      if (s == nil
	        || ([s caseInsensitiveCompare: @"keep-alive"] != NSOrderedSame))
		{
		  [self setShouldClose: YES];
		}
	    }
	}

      /* We will close this connection if the maximum number of requests
       * or maximum request duration has been exceeded.
       */
      if (requests >= conf->maxConnectionRequests)
	{
	  [self setShouldClose: YES];
	}
      else if (duration >= conf->maxConnectionDuration)
	{
	  [self setShouldClose: YES];
	}

      /* Ensure that we send a connection close if we are about to drop
       * the connection.
       */
      if ([self shouldClose] == YES)
        {
	  [response setHeader: @"Connection"
			value: @"close"
		   parameters: nil];
	}

      enumerator = [[response allHeaders] objectEnumerator];
      while ((hdr = [enumerator nextObject]) != nil)
	{
	  [out appendData: [hdr rawMimeData]];
	}
      if ([raw length] > 0)
	{
	  [out appendData: raw];
	}
      else
	{
	  [out appendBytes: "\r\n" length: 2];	// Terminate headers
	}
      data = out;
    }

  if (YES == conf->verbose && NO == quiet)
    {
      [server _log: @"Response %@ - %@", self, data];
    }
  [nc removeObserver: self
		name: NSFileHandleReadCompletionNotification
	      object: handle];
  [handle performSelector: @selector(writeInBackgroundAndNotify:)
                 onThread: ioThread->thread
               withObject: data
            waitUntilDone: NO];


  /* If this connection is not closing and excess data has been read,
   * we may continue dealing with incoming data before the write
   * has completed.
   */
  if ([self shouldClose] == YES)
    {
      [self setExcess: nil];
    }
  else
    {
      NSData	*more = [self excess];

      if (more != nil)
	{
	  [more retain];
	  [self setExcess: nil];
	  [self reset];
          [self _didData: more];
	  [more release];
	}
    }
}

- (WebServerResponse*) response
{
  if (nil == response)
    {
      response = [WebServerResponse new];
      [response setWebServerConnection: self];
    }
  return response;
}

- (NSTimeInterval) connectionDuration: (NSTimeInterval)now
{
  if (connectionStart > 0.0)
    {
      return now - connectionStart;
    }
  return 0.0;
}

- (void) setAddress: (NSString*)aString
{
  ASSIGN(address, aString);
}

- (void) setAgent: (NSString*)aString
{
  ASSIGN(agent, aString);
}

- (void) setConnectionStart: (NSTimeInterval)when
{
  connectionStart = when;
}

- (void) setExcess: (NSData*)d
{
  ASSIGNCOPY(excess, d);
}

- (void) setParser: (GSMimeParser*)aParser
{
  ASSIGN(parser, aParser);
}

- (void) setProcessing: (BOOL)aFlag
{
  [ioThread->threadLock lock];
  if (YES == aFlag)
    {
      if (owner != ioThread->processing)
	{
	  GSLinkedListRemove(self, owner);
	  GSLinkedListInsertAfter(self, ioThread->processing,
	    ioThread->processing->tail);
	}
    }
  else
    {
      if (owner != ioThread->readwrites)
	{
	  GSLinkedListRemove(self, owner);
	  GSLinkedListInsertAfter(self, ioThread->readwrites,
	    ioThread->readwrites->tail);
	}
    }
  [ioThread->threadLock unlock];
}

- (void) setRequestEnd: (NSTimeInterval)when
{
  NSTimeInterval	ti = when - requestStart;

  if (ti > 0.0)
    {
      requestStart = 0.0;
      duration += ti;
      requests++;
    }
}

- (void) setRequestStart: (NSTimeInterval)when
{
  requestStart = when;
}

- (void) setResult: (NSString*)aString
{
  ASSIGN(result, aString);
}

- (void) setShouldClose: (BOOL)aFlag
{
  shouldClose = aFlag;
}

- (void) setSimple: (BOOL)aFlag
{
  simple = aFlag;
}

- (void) setTicked: (NSTimeInterval)t
{
  [ioThread->threadLock lock];
  ticked = t;
  GSLinkedListMoveToTail(self, owner);
  [ioThread->threadLock unlock];
}

- (void) setUser: (NSString*)aString
{
  ASSIGN(user, aString);
}

- (BOOL) shouldClose
{
  return shouldClose;
}

- (BOOL) simple
{
  return simple;
}

- (void) start
{
  NSHost	*host;

  host = nil;
  if (YES == conf->reverse && nil == result)
    {
      host = [NSHost hostWithAddress: address];
      if (nil == host)
	{
	  result = @"HTTP/1.0 403 Bad client host";
	}
    }
  else
    {
      host = nil;
    }

  if (YES == conf->verbose && NO == quiet)
    {
      if (host == nil)
	{
	  [server _log: @"%@ connect", self];
	}
      else
	{
	  [server _log: @"%@ connect from %@", self, [host name]];
	}
    }

  if (YES == ssl)
    {
      BOOL	ok;

      ok = [handle sslAccept];

      [ioThread->threadLock lock];
      ticked = [NSDateClass timeIntervalSinceReferenceDate];
      GSLinkedListRemove(self, owner);
      GSLinkedListInsertAfter(self, ioThread->readwrites,
	ioThread->readwrites->tail);
      [ioThread->threadLock unlock];

      if (NO == ok)			// Reset time of last I/O
	{
	  if (NO == quiet)
	    {
	      [server _log: @"SSL accept fail on (%@).", address];
	    }
	  [self end];
	}
    }

  [nc addObserver: self
	 selector: @selector(_didWrite:)
	     name: GSFileHandleWriteCompletionNotification
	   object: handle];

  if (nil == result)
    {
      buffer = [[NSMutableDataClass alloc] initWithCapacity: 1024];
      [nc addObserver: self
	     selector: @selector(_didRead:)
		 name: NSFileHandleReadCompletionNotification
	       object: handle];
      [handle performSelector: @selector(readInBackgroundAndNotify)
		     onThread: ioThread->thread
		   withObject: nil
		waitUntilDone: NO];
    }
  else
    {
      NSString	*body;

      [self setShouldClose: YES];

      if ([result rangeOfString: @" 503 "].location != NSNotFound)
	{
	  [server _alert: result];
	  body = [result stringByAppendingString:
	    @"\r\nRetry-After: 120\r\n\r\n"];
	}
      else
	{
	  if (YES == quiet)
	    {
	      [server _log: result];
	    }
	  body = [result stringByAppendingString: @"\r\n\r\n"];
        }
      [handle performSelector: @selector(writeInBackgroundAndNotify:)
		     onThread: ioThread->thread
		   withObject: [body dataUsingEncoding: NSASCIIStringEncoding]
		waitUntilDone: NO];
    }
}

- (BOOL) verbose
{
  return conf->verbose;
}

- (void) _didData: (NSData*)d
{
  NSString		*method = @"";
  NSString		*query = @"";
  NSString		*path = @"";
  NSString		*version = @"";
  GSMimeDocument	*doc;

  // Mark as having had I/O ... not idle.
  ticked = [NSDateClass timeIntervalSinceReferenceDate];

  if (parser == nil)
    {
      uint8_t		*bytes;
      NSUInteger	length;
      NSUInteger	pos;

      /*
       * If we are starting to read a new request, record the request
       * startup time.
       */
      if ([self requestDuration: ticked] == 0.0)
	{
	  [self setRequestStart: ticked];
	}

      /*
       * Add new data to any we already have and search for the end
       * of the initial request line.
       */
      [buffer appendData: d];
      bytes = [buffer mutableBytes];
      length = [buffer length];

      /*
       * Some buggy browsers/libraries add a CR-LF after POSTing data,
       * so if we are using a connection which has been kept alive,
       * we must eat up that initial white space.
       */
      while (length > 0 && isspace(bytes[0]))
        {
	  bytes++;
	  length--;
	}

      /* Try to find end of first line (the request line).
       */
      for (pos = 0; pos < length; pos++)
	{
	  if (bytes[pos] == '\n')
	    {
	      break;
	    }
	}

      /*
       * Attackers may try to send too much data in the hope of causing
       * a buffer overflow ... so we try to detect it here.
       */
      if (pos >= conf->maxRequestSize)
	{
	  NSData	*data;

	  [server _log: @"Request too long ... rejected"];
	  [self setShouldClose: YES];
	  [self setResult: @"HTTP/1.0 413 Request data too long"];
	  [nc removeObserver: self
			name: NSFileHandleReadCompletionNotification
		      object: handle];
	  data = [@"HTTP/1.0 413 Request data too long\r\n\r\n"
	    dataUsingEncoding: NSASCIIStringEncoding];
	  [handle performSelector: @selector(writeInBackgroundAndNotify:)
			 onThread: ioThread->thread
		       withObject: data
		    waitUntilDone: NO];
	  return;
	}

      if (pos == length)
	{
	  /* Needs more data.
	   */
	  [handle performSelector: @selector(readInBackgroundAndNotify)
			 onThread: ioThread->thread
		       withObject: nil
		    waitUntilDone: NO];
	  return;
	}
      else
	{
	  NSUInteger	back = pos;
	  NSUInteger	start = 0;
	  NSUInteger	end;

	  /*
	   * Trim trailing whitespace from request line.
	   */
	  bytes[pos++] = '\0';
	  while (back > 0 && isspace(bytes[--back]))
	    {
	      bytes[back] = '\0';
	    }

	  /*
	   * Store the actual command string used.
	   */
	  [command release];
	  command = [NSStringClass alloc];
	  command = [command initWithUTF8String: (const char*)bytes];

	  /*
	   * Remove and store trailing HTTP version extension
	   */
	  while (back > 0 && !isspace(bytes[back]))
	    {
	      back--;
	    }
	  if (isspace(bytes[back])
	    && strncmp((char*)bytes + back + 1, "HTTP/", 5) == 0)
	    {
	      bytes[back] = '\0';
	      end = back + 6;
	      version
		= [NSStringClass stringWithUTF8String: (char*)bytes + end];
	      if ([version floatValue] < 1.1)
		{
		  [self setShouldClose: YES];	// Not persistent.
		}
	    }
	  else
	    {
	      back = strlen((const char*)bytes);
	      [self setSimple: YES];	// Old style simple request.
	      [self setShouldClose: YES];	// Not persistent.
	    }

	  /*
	   * Remove leading white space.
	   */
	  start = 0;
	  while (start < back && isspace(bytes[start]))
	    {
	      start++;
	    }

	  /*
	   * Extract method string as uppercase value.
	   */
	  end = start;
	  while (end < back && !isspace(bytes[end]))
	    {
	      if (islower(bytes[end]))
		{
		  bytes[end] = toupper(bytes[end]);
		}
	      end++;
	    }
	  bytes[end++] = '\0';
	  method = [NSStringClass stringWithUTF8String: (char*)bytes + start];

	  /*
	   * Extract path string.
	   */
	  start = end;
	  while (start < back && isspace(bytes[start]))
	    {
	      start++;
	    }
	  end = start;
	  while (end < back && bytes[end] != '?')
	    {
	      end++;
	    }
	  if (bytes[end] == '?')
	    {
	      /*
	       * Extract query string.
	       */
	      bytes[end++] = '\0';
	      query = [NSStringClass stringWithUTF8String: (char*)bytes + end];
	      if (query == nil)
		{
		  NSData	*data;

		  [server _log: @"Request query string not valid UTF8"];
		  [self setShouldClose: YES];	// Not persistent.
		  [self setResult: @"HTTP/1.0 413 Query string not UTF8"];
		  data = [@"HTTP/1.0 413 Query string not UTF8\r\n\r\n"
		    dataUsingEncoding: NSASCIIStringEncoding];
		  [handle performSelector:
		    @selector(writeInBackgroundAndNotify:)
				 onThread: ioThread->thread
			       withObject: data
			    waitUntilDone: NO];
		  return;
		}
	    }
	  else
	    {
	      bytes[end] = '\0';
	    }
	  path = [NSStringClass stringWithUTF8String: (char*)bytes + start];

	  if ([method isEqualToString: @"GET"] == NO
	    && [method isEqualToString: @"POST"] == NO)
	    {
	      NSData	*data;

	      [self setShouldClose: YES];	// Not persistent.
	      [self setResult: @"HTTP/1.0 501 Not Implemented"];
	      data = [@"HTTP/1.0 501 Not Implemented\r\n\r\n"
		dataUsingEncoding: NSASCIIStringEncoding];
	      [handle performSelector: @selector(writeInBackgroundAndNotify:)
			     onThread: ioThread->thread
			   withObject: data
			waitUntilDone: NO];
	      return;
	    }

	  /*
	   * Any left over data is passed to the mime parser.
	   */
	  if (pos < length)
	    {
	      memmove(bytes, &bytes[pos], length - pos);
	      [buffer setLength: length - pos];
	      d = AUTORELEASE(RETAIN(buffer));
	    }

	  parser = [GSMimeParser new];
	  [parser setIsHttp];
	  if ([method isEqualToString: @"POST"] == NO)
	    {
	      /* If it's not a POST, we don't need a body.
	       */
	      [parser setHeadersOnly];
	    }
	  [parser setDefaultCharset: @"utf-8"];

	  doc = [parser mimeDocument];

	  [doc setHeader: @"x-http-method"
		   value: method
	      parameters: nil];
	  [doc setHeader: @"x-http-path"
		   value: path
	      parameters: nil];
	  [doc setHeader: @"x-http-query"
		   value: query
	      parameters: nil];
	  [doc setHeader: @"x-http-scheme"
		   value: ((conf->secureProxy || ssl) ? @"https" : @"http")
	      parameters: nil];
	  [doc setHeader: @"x-http-version"
		   value: version
	      parameters: nil];

	  if (pos >= length)
	    {
	      // Needs more data.
	      [handle performSelector: @selector(readInBackgroundAndNotify)
			     onThread: ioThread->thread
			   withObject: nil
			waitUntilDone: NO];
	      return;
	    }
	  // Fall through to parse remaining data with mime parser
	}
    }

  doc = [parser mimeDocument];
  method = [[doc headerNamed: @"x-http-method"] value];

  if ([self moreBytes: [d length]] > conf->maxBodySize)
    {
      NSData	*data;

      [server _log: @"Request body too long ... rejected"];
      [self setShouldClose: YES];	// Not persistent.
      [self setResult: @"HTTP/1.0 413 Request body too long"];
      data = [@"HTTP/1.0 413 Request body too long\r\n\r\n"
	dataUsingEncoding: NSASCIIStringEncoding];
      [handle performSelector: @selector(writeInBackgroundAndNotify:)
		     onThread: ioThread->thread
		   withObject: data
		waitUntilDone: NO];
      return;
    }
  else if ([parser parse: d] == NO)
    {
      if ([parser isComplete] == YES)
	{
	  [server _process1: self];
	}
      else
	{
	  NSData	*data;

	  [server _log: @"HTTP parse failure - %@", parser];
          [self setShouldClose: YES];	// Not persistent.
          [self setResult: @"HTTP/1.0 400 Bad Request"];
          data = [@"HTTP/1.0 400 Bad Request\r\n\r\n"
            dataUsingEncoding: NSASCIIStringEncoding];
	  [handle performSelector: @selector(writeInBackgroundAndNotify:)
			 onThread: ioThread->thread
		       withObject: data
		    waitUntilDone: NO];
	  return;
	}
    }
  else if (([parser isComplete] == YES)
    || ([parser isInHeaders] == NO && ([method isEqualToString: @"GET"])))
    {
      [server _process1: self];
    }
  else
    {
      [handle performSelector: @selector(readInBackgroundAndNotify)
		     onThread: ioThread->thread
		   withObject: nil
		waitUntilDone: NO];
    }
}

- (void) _didRead: (NSNotification*)notification
{
  NSDictionary		*dict;
  NSData		*d;
  NSTimeInterval	now = [NSDateClass timeIntervalSinceReferenceDate];

  NSAssert([notification object] == handle, NSInternalInconsistencyException);
  [self setTicked: now];

  dict = [notification userInfo];
  d = [dict objectForKey: NSFileHandleNotificationDataItem];

  if ([d length] == 0)
    {
      if (parser == nil)
	{
	  if ([buffer length] == 0)
	    {
	      /*
	       * Don't log if we have already reset after handling
	       * a request.
	       * Don't log this in quiet mode as it could just be a
	       * test connection that we are ignoring.
	       */
	      if (NO == quiet && [self hasReset] == NO)
		{
		  [server _log: @"%@ read end-of-file in empty request", self];
		}
	    }
	  else
	    {
	      [server _log: @"%@ read end-of-file in partial request - %@",
		self, buffer];
	    }
	}
      else
	{
	  [server _log: @"%@ read end-of-file in incomplete request - %@",
	    self, [parser mimeDocument]];
	}
      [self end];
      return;
    }

  if (YES == conf->verbose && NO == quiet)
    {
      [server _log: @"Data read on %@ ... %@", self, d];
    }

  [self _didData: d];
}

- (void) _didWrite: (NSNotification*)notification
{
  NSTimeInterval	now = [NSDateClass timeIntervalSinceReferenceDate];

  NSAssert([notification object] == handle, NSInternalInconsistencyException);
  [self setTicked: now];

  if ([self shouldClose] == YES)
    {
      [self end];
    }
  else
    {
      NSTimeInterval	t = [self requestDuration: now];

      if (t > 0.0)
	{
	  [self setRequestEnd: now];
	  if (NO == quiet && YES == conf->durations)
	    {
	      [server _log: @"%@ end of request (duration %g)", self, t];
	    }
	}
      else
	{
	  if (NO == quiet && YES == conf->durations)
	    {
	      [server _log: @"%@ reset", self];
	    }
	}
      if (NO == quiet)
	{
          [server _audit: self];
	}
      [self reset];
      [nc addObserver: self
	     selector: @selector(_didRead:)
		 name: NSFileHandleReadCompletionNotification
	       object: handle];
      [handle performSelector: @selector(readInBackgroundAndNotify)
		     onThread: ioThread->thread
		   withObject: nil
		waitUntilDone: NO];
    }
}

@end