//  SwiftLogger.swift
//
//  Copyright (c) 2016 Nicholas Molyneux
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

/*
HOPES

//step 1: create a singleton instance
static let log = SwiftLogger(`optionalconfig`)

//step 2: log stuff
log.info("message")         info log
log.debug("message")

//step 3: read the logs
log.getLogs()

//step 4: purge the logs
log.purgeLogs()

todo:
>async
>figure out how to call a method on application exit/crash etc so we can flush the tail
>write some stuff to the log on startup? maybe as a diagnostics setting?
*/

import Foundation

@objc
public protocol SwiftLoggerDelegate: NSObjectProtocol {
    /**
        Advises the delegate that the current tail has been flushed to disk.
        - Parameter wasManual: Determines if the flush was caused by a user (true) or by the internals (false)
    */
    optional func swiftLogger_didFlushTailToDisk(wasManual: Bool)
    /**
        Advises the delegate that a message was written to the tail
        - Parameter message: The message that was written to the tail
    */
    optional func swiftLogger_didWriteLogToTail(message: String)
}

public class SwiftLogger {
    /**Determines if logging can occur. This is set to false if problems were encountered during initialization*/
    var loggingIsActive: Bool = true
    
    /**NSFileManager singleton instance*/
    private let _fileManager: NSFileManager = NSFileManager.defaultManager()
    /**Logging location*/
    private let _logPath: String
    /**The size of the tail before writing a disk, in bytes, this is effectively slightly smaller than the size of each file. Once the tail contains exactly or more bytes than specified here, it is written to a file.*/
    private let _fileSize: Int
    /**Contains the current tail that hasn't been flushed to disk*/
    private var _currentLogTail: String = ""
    /**The next file number that will be used to create log files*/
    private var _nextFileNumber: Int = 1
    /**Generates the name and file path for the next file that will be written to disk*/
    private var _nextFileName: String { get { return self._logPath + "/" + self._logFileNamePrefix + String(format: "%09d", self._nextFileNumber) + ".txt" } }
    /**The prefix for files created by the logger*/
    private let _logFileNamePrefix: String = "log_"
    private let _delegate: SwiftLoggerDelegate?
    //log levels. you might be asking... why ERRR and FATL? it's because im kinda OCD about how the log looks and this makes everything line up vertically.
    private let _LOGLEVEL_INFO =     "INFO"
    private let _LOGLEVEL_DEBUG =    "DEBG"
    private let _LOGLEVEL_WARN =     "WARN"
    private let _LOGLEVEL_ERROR =    "ERRR"
    private let _LOGLEVEL_FATAL =    "FATL"
    
    /**Queue for asynchronous operations for writing to the tail that will be performed by the logger*/
//    private let _dispatch_write_queue = dispatch_queue_create("SwiftLogger-Write", nil)
//    /**Queue for synchronous flushing tasks so we can prevent multiple calls to it*/
//    private let _dispatch_flush_queue = dispatch_queue_create("SwiftLogger-Flush", nil)
//    /**Queue for synchronous purging tasks so we can prevent multiple calls to it*/
//    private let _dispatch_purge_queue = dispatch_queue_create("SwiftLogger-Purge", nil)
//    private let _dispatch_group = dispatch_group_create()
    private let _dispatch_queue = dispatch_queue_create("SwiftLogger", nil)
    
    /**
        Creates an instance of the logger
    
        - Parameter directory: The directory in which to save log files. Defaults to `.ApplicationSupportDirectory`.
        - Parameter domain: The file system domain to search for the directory. Defaults to `.UserDomainMask`.
        - Parameter explodeOnFailureToInit: If true, a fatal error will occur if the initialization fails. Defaults to true assuming that the application is dependent on logging. If this is not the case, simply use false here, and only `debugPrint` will be advise you that no logging will occur, denoted by "SWIFTLOGGER-NOLOG".
        - Parameter fileSize: The size of the tail before writing a disk, in bytes, this is effectively the size of each file
    */
    init(
        delegate: SwiftLoggerDelegate? = nil,
        directory: NSSearchPathDirectory = .ApplicationSupportDirectory,
        domain: NSSearchPathDomainMask = .UserDomainMask,
        explodeOnFailureToInit: Bool = true,
        fileSize: Int = 1000) {
            self._delegate = delegate
            self._fileSize = fileSize
            //create the logging directory
            let topDirectory: NSString = NSSearchPathForDirectoriesInDomains(directory, .UserDomainMask, true).first!
            self._logPath = topDirectory.stringByAppendingPathComponent("SwiftLogger")
            if !self._fileManager.fileExistsAtPath(self._logPath) {
                //it would be unfortunate if this blew up, but it will also tell you, immediately, that there's a config problem
                do {
                    try self._fileManager.createDirectoryAtPath(self._logPath, withIntermediateDirectories: false, attributes: nil)
                } catch {
                    debugPrint("SWIFTLOGGER", "failed getting log directory due to", error)
                    if explodeOnFailureToInit {
                        fatalError("SWIFTLOGGER failed getting log directory due to: \(error)")
                    } else {
                        debugPrint("SWIFTLOGGER", "no logging will occur, due to the failure above.")
                        self.loggingIsActive = false
                    }
                    return
                }
            }
            //get the name of the last file we wrote so we can get the number
            var lastFile:String?
            do {
                lastFile = try self._fileManager.contentsOfDirectoryAtPath(self._logPath)
                    .filter { $0.hasPrefix(self._logFileNamePrefix) }
                    .sort()
                    .last
            } catch {
                debugPrint("SWIFTLOGGER", "failed getting current contents of logging directory", error)
                if explodeOnFailureToInit {
                    fatalError("SWIFTLOGGER failed getting current contents of logging directory due to: \(error)")
                } else {
                    debugPrint("SWIFTLOGGER", "no logging will occur, due to the failure above.")
                    self.loggingIsActive = false
                }
            }
            if let lf = lastFile where lf != "" {
                let trimmed = lf
                    .stringByReplacingOccurrencesOfString(self._logFileNamePrefix, withString: "", options: [.CaseInsensitiveSearch, .AnchoredSearch])
                    .stringByReplacingOccurrencesOfString(".txt", withString: "", options: [.CaseInsensitiveSearch, .AnchoredSearch, .BackwardsSearch])
                if let i = Int(trimmed) {
                    self._nextFileNumber = i + 1
                } else {
                    debugPrint("SWIFTLOGGER", "failed parsing last log file number", lf, "trimmed", trimmed)
                }
            }
    }
    
    func info<T>(objectArgs: T...) {
        //before we process anything, get the time so know exactly when the logging occurred
        let timestamp = NSDate()
        let messages = objectArgs.map({ self._getMessageFromObject($0) }).filter({ $0 != "" })
        //now that we have all necessary data, send dispatch the work to write
//        dispatch_async(self._dispatch_queue) {
            self._formatAndWrite(self._LOGLEVEL_INFO, timestamp: timestamp, messages: messages)
//        }
    }
    
    private func _getMessageFromObject<T>(o: T) -> String {
        if let c = o as? CustomDebugStringConvertible {
            return c.debugDescription
        } else if let c = o as? CustomStringConvertible {
            return c.description
        } else if let c = o as? Streamable {
            var targ = String()
            c.writeTo(&targ)
            return targ
        } else {
            //if debugprint can, and i cant, well that sux and it needs to be figured out
            debugPrint("SWIFTLOGGER", "attempted to log your object, but it wasn't a conforming type!", o)
            return ""
        }
    }
    
    /**
        Prepares a batch of message to be written by formatting them and then writes the batch to the log file.
    
        - Parameter logLevel: The log level for the batch of messages (_LOGLEVEL).
        - Parameter timestamp: The time at which the logger was called to process a logging event.
        - Parameter messages: The unformatted messages to log.
    */
    private func _formatAndWrite(logLevel: String, timestamp: NSDate, messages: [String]) {
        /*EXPECTED FORMAT
        INFO:01/23/16 13:45:123456 PDT
        >this is the first in the batch
        >this is the second in the batch
        ERROR:01/23/16 13:45:123456 PDT
        >this is the next one but it's an error
        */
        var clean = "\(logLevel):\(dateFormatters._default.stringFromDate(timestamp))\n"
        clean += messages.map { ">\($0)" }.joinWithSeparator("\n")
        self._write(clean)
    }
    
    /**
        Writes the message to the current tail
    */
    private func _write(message: String) {
        if !self.loggingIsActive {
            debugPrint("SWIFTLOGGER-NOLOG", message)
            return
        }
        //append to the log
        //if there's already stuff in the tail, slap a line break in there to break up the messages
        if self._currentLogTail != "" {
            self._currentLogTail += "\n" + message
        } else {
            self._currentLogTail += message
        }
        //let the delegate know it's been written
        self._delegate?.swiftLogger_didWriteLogToTail?(message)
        //check if we need to flush to disk
        if self._fileSize < self._currentLogTail.utf8.count {
            self._flushTailToDisk(false)
        }
    }
    
    /**
        Manually flushes the tail to a file on the disk.
    */
    public func flushTailToDisk() {
        self._flushTailToDisk(true)
    }
    /**
        Flushes the tail to a file on the disk.
    */
    internal func _flushTailToDisk(manualFlush: Bool) {
        if !self.loggingIsActive {
            return
        }
        //mutex lock this method to prevent multiple calls to this at once
//        dispatch_sync(self._dispatch_queue) {
            if self._currentLogTail == "" {
                return
            }
            let finalPath = self._nextFileName
            debugPrint("SWIFTLOGGER", "final write path", finalPath)
            do {
                try self._currentLogTail.writeToFile(finalPath, atomically: true, encoding: NSUTF8StringEncoding)
            } catch {
                debugPrint("SWIFTLOGGER", "failed attempting to write file to a path", error)
                return
            }
            //reset the tail and set our next file number
            self._currentLogTail = ""
            self._nextFileNumber += 1
            //let the delegate know the tail has been flushed
            self._delegate?.swiftLogger_didFlushTailToDisk?(manualFlush)
//        }
    }
    
    //todo: throw for errors retrieving files? not sure a user would want to handle that. i think i would
    /**
        Gets all log files.
    
        - Returns: a dictionary containing the name of the file as the key and the actual contents as the value. nil is returned if there was a problem getting the files.
    */
    func getLogs() -> [String:String]? {
        if !self.loggingIsActive {
            return nil
        }
        var filesOpt:[String]?
        do {
            filesOpt = try self._fileManager.contentsOfDirectoryAtPath(self._logPath)
                .filter { $0.hasPrefix(self._logFileNamePrefix) }
                .sort()
        } catch {
            debugPrint("SWIFTLOGGER", "failed getting contents of logging directory", self._logPath, error)
        }
        guard let files = filesOpt else {
            return nil
        }
        var logs = [String:String]()
        for file in files {
            if let dataContents = self._fileManager.contentsAtPath(self._logPath + "/" + file) {
                if let contents = String(data: dataContents, encoding: NSUTF8StringEncoding) {
                    logs[file] = contents
                } else {
                    debugPrint("SWIFTLOGGER", "failed encoding data to utf8", self._logPath, file)
                }
            } else {
                debugPrint("SWIFTLOGGER", "failed getting contents of file at path", self._logPath, file)
            }
        }
        return logs
    }
    
    //todo: figure out how to do a mutex lock that prevents multiple calls to this method AND prevents writing/getting logs
    /**
        Purges log files
    
        Generally, you only really need to purge specific files if you're pulling files out to consume them while the application is still potentially logging. This prevents you from purging files that were created during the time your application was consuming the pulled files.
    
        - Parameter filesToPurge: a list of file names to purge, usually provided by the `getLogs()` function. All logs are purged if nil is passed
    */
    func purgeLogs(filesToPurge: [String]?) {
        if !self.loggingIsActive {
            return
        }
//        dispatch_sync(self._dispatch_queue) {
            var files:[String]?
            if filesToPurge == nil {
                do {
                    files = try self._fileManager.contentsOfDirectoryAtPath(self._logPath)
                        .filter { $0.hasPrefix(self._logFileNamePrefix) }
                } catch {
                    debugPrint("SWIFTLOGGER", "failed getting contents of logging directory for purge", self._logPath, error)
                }
            }
            guard let fs = files else {
                return
            }
            for file in fs {
                do {
                    try self._fileManager.removeItemAtPath(self._logPath + "/" + file)
                } catch {
                    debugPrint("SWIFTLOGGER", "failed purging file at path", self._logPath, "filename", file)
                }
            }
//        }
    }
    
    // MARK - utilities
    private class dateFormatters: NSDateFormatter {
        init(_ format: String) {
            super.init()
            self.dateFormat = format
        }
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        /**default logging format: 01/20/16 12:34:56.789 PDT **/
        private static let _default = dateFormatters("MM/dd/yy HH:mm:ss.SSS zzz")
    }
}

