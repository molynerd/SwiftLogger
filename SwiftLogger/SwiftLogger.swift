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
>documentation: advise user to put shutdown method in on-crash or on-exit area of app
>write some stuff to the log on startup? maybe as a diagnostics setting?
>tests for delegate
*/

import Foundation

enum SwiftLoggerGetLogsError: ErrorType {
    /**Failed getting contents of logging directory*/
    case FailedEnumeratingDirectory(error: ErrorType)
    /**Someone developing SwiftLogger screwed something up. You should never ever see this. Ever.*/
    case Bug(errorMessage: String)
}

//todo: can this be written without objc declaration?
@objc
public protocol SwiftLoggerDelegate {
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
    /**Generates the name and file path for the next file that will be written to disk*/
    private var _nextFileName: String { get { return self._logPath + "/" + self._logFileNamePrefix + String(format: "%09d", self._protected.nextFileNumber) + ".txt" } }
    /**The prefix for files created by the logger*/
    private let _logFileNamePrefix: String = "log_"
    private let _delegate: SwiftLoggerDelegate?
    private let _writeToDebugPrint: Bool
    
//    /**Queue for mutex locking so we can guarantee some thread-safety*/
//    private let _dispatch_mutex = dispatch_queue_create("SwiftLogger-Mutex", nil)
    /**Contains mutable variables that need thread protection*/
    private let _protected = threadProtected()
    /**Mutex lock object for preventing read/write operations on log files from happening simultaneously*/
    private let _logFileLock = NSObject()
    
    /**
        Creates an instance of the logger
    
        - Parameter delegate: A delegate to receive messages about what the logger is doing
        - Parameter alsoWriteToDebugPrint: if true, all log messages are also written to debugPrint, denoted by "SWIFTLOGGER-LOG-MESSAGE-MESSAGE"
        - Parameter directory: The directory in which to save log files. Defaults to `.ApplicationSupportDirectory`.
        - Parameter domain: The file system domain to search for the directory. Defaults to `.UserDomainMask`.
        - Parameter explodeOnFailureToInit: If true, a fatal error will occur if the initialization fails. Defaults to true assuming that the application is dependent on logging. If this is not the case, simply use false here, and only `debugPrint` will be advise you that no logging will occur, denoted by "SWIFTLOGGER-NOLOG-MESSAGE-MESSAGE".
        - Parameter fileSize: The size of the tail before writing a disk, in bytes, this is effectively the size of each file
    */
    init(
        delegate: SwiftLoggerDelegate? = nil,
        alsoWriteToDebugPrint: Bool = false,
        directory: NSSearchPathDirectory = .ApplicationSupportDirectory,
        domain: NSSearchPathDomainMask = .UserDomainMask,
        explodeOnFailureToInit: Bool = true,
        fileSize: Int = 1000) {
            self._delegate = delegate
            self._writeToDebugPrint = alsoWriteToDebugPrint
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
                    self._protected.nextFileNumber = i + 1
                } else {
                    debugPrint("SWIFTLOGGER", "failed parsing last log file number", lf, "trimmed", trimmed)
                }
            }
    }
    
    /**Info level log*/
    func info<T>(objectArgs: T...) {
        self._parseEntry(self._LOGLEVEL_INFO, objectArgs: objectArgs)
    }
    func debug<T>(objectArgs: T...) {
        self._parseEntry(self._LOGLEVEL_DEBUG, objectArgs: objectArgs)
    }
    func warn<T>(objectArgs: T...) {
        self._parseEntry(self._LOGLEVEL_WARN, objectArgs: objectArgs)
    }
    func error<T>(objectArgs: T...) {
        self._parseEntry(self._LOGLEVEL_ERROR, objectArgs: objectArgs)
    }
    func fatal<T>(objectArgs: T...) {
        self._parseEntry(self._LOGLEVEL_FATAL, objectArgs: objectArgs)
    }
    
    //todo: theres a potential to make this func public, so that you could set the log level programmatically, but i'm not sure how to force the coder to use one of the LOGLEVEL constants. i could just do a switch... but i feel like that's kinda lazy and might impact performance
    /**Middle function for logging, all general purpose logging functions filter into this function*/
    private func _parseEntry<T>(logLevel: String, objectArgs: T...) {
        //before we process anything, get the time so know exactly when the logging occurred
        let timestamp = NSDate()
        let messages = objectArgs.map({ self._getMessageFromObject($0) }).filter({ $0 != "" })
        self._formatAndWrite(self._LOGLEVEL_INFO, timestamp: timestamp, messages: messages)
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
            debugPrint("SWIFTLOGGER-NOLOG-MESSAGE", message)
            return
        }
        //append to the log
        //if there's already stuff in the tail, slap a line break in there to break up the messages
        if self._protected.currentLogTail != "" {
            self._protected.currentLogTail += "\n" + message
        } else {
            self._protected.currentLogTail += message
        }
        if self._writeToDebugPrint {
            debugPrint("SWIFTLOGGER-LOG-MESSAGE", message)
        }
        //let the delegate know it's been written
        self._delegate?.swiftLogger_didWriteLogToTail?(message)
        //check if we need to flush to disk
        if self._fileSize < self._protected.currentLogTail.utf8.count {
            self._flushTailToDisk(false)
        }
    }
    
    /**
        Flushes the tail to a file on the disk.
    
        - Parameter manualFlush: determines if the flush was called by a user (true) or by the internals (false)
    */
    private func _flushTailToDisk(manualFlush: Bool) {
        if !self.loggingIsActive {
            debugPrint("SWIFTLOGGER-NOLOG", "attempted to flush but logging inactive")
            return
        }
        if self._protected.currentLogTail == "" {
            return
        }
        let finalPath = self._nextFileName
        //thread-safety: make sure this is only ever called once at a time, and only one of reading/writing logs should ever be executing at once
        debugPrint("SWIFTLOGGER", "final write path", finalPath)
        do {
            objc_sync_enter(self._logFileLock)
            try self._protected.currentLogTail.writeToFile(finalPath, atomically: true, encoding: NSUTF8StringEncoding)
            objc_sync_exit(self._logFileLock)
        } catch {
            objc_sync_exit(self._logFileLock)
            debugPrint("SWIFTLOGGER", "failed attempting to write file to a path", error)
            return
        }
        //reset the tail and set our next file number
        self._protected.currentLogTail = ""
        self._protected.nextFileNumber += 1
        //let the delegate know the tail has been flushed
        self._delegate?.swiftLogger_didFlushTailToDisk?(manualFlush)
    }
    
    /**
        Gets all log files.
    
        - Returns: a dictionary containing the name of the file as the key and the actual contents as the value.
        - Throws: `SwiftLoggerGetLogsError.FailedEnumeratingDirectory(ErrorType)` if there was an issue getting the contents of the logging directory, includes the error thrown by the file manager. `SwiftLoggerGetLogsError.Bug(String)` if something seriously weird happens.
    */
    func getLogs() throws -> [String:String] {
        if !self.loggingIsActive {
            debugPrint("SWIFTLOGGER-NOLOG", "attempted to get logs but logging inactive")
            return [String:String]()
        }
        //thread-safety: make sure this is only ever called once at a time, and only one of reading/writing logs should ever be executing at once
        objc_sync_enter(self._logFileLock)
        var filesOpt:[String]?
        do {
            filesOpt = try self._fileManager.contentsOfDirectoryAtPath(self._logPath)
                .filter { $0.hasPrefix(self._logFileNamePrefix) }
                .sort()
        } catch {
            debugPrint("SWIFTLOGGER", "failed getting contents of logging directory", self._logPath, error)
            objc_sync_exit(self._logFileLock)
            throw SwiftLoggerGetLogsError.FailedEnumeratingDirectory(error: error)
        }
        guard let files = filesOpt else {
            //this should never happen. if someone sees this, we've really f'd this method
            objc_sync_exit(self._logFileLock)
            throw SwiftLoggerGetLogsError.Bug(errorMessage: "Files optional could not be unwrapped")
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
        objc_sync_exit(self._logFileLock)
        return logs
    }
    
    /**
        Purges log files
    
        Generally, you only really need to purge specific files if you're pulling files out to consume them while the application is still potentially logging. This prevents you from purging files that were created during the time your application was consuming the pulled files.
    
        - Parameter filesToPurge: a list of file names to purge, usually provided by the `getLogs()` function. All logs are purged if nil is passed
    */
    func purgeLogs(filesToPurge: [String]?) {
        if !self.loggingIsActive {
            return
        }
        //thread-safety: make sure this is only ever called once at a time, and only one of reading/writing logs should ever be executing at once
        objc_sync_enter(self._logFileLock)
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
            objc_sync_exit(self._logFileLock)
            return
        }
        for file in fs {
            let fileName = self._logPath + "/" + file
            if !self._fileManager.fileExistsAtPath(fileName) {
                objc_sync_exit(self._logFileLock)
                return
            }
            do {
                try self._fileManager.removeItemAtPath(fileName)
            } catch {
                debugPrint("SWIFTLOGGER", "failed purging file at path", self._logPath, "filename", file)
            }
        }
        objc_sync_exit(self._logFileLock)
    }
    
    /**
        Guarantees all log data is flushed to disk by blocking the current thread until completion
    */
    func shutdown() {
        self._flushTailToDisk(true)
    }
    
    // MARK - utilities
    //log levels. you might be asking... why ERRR and FATL? it's because im kinda OCD about how the log looks and this makes everything line up vertically.
    private let _LOGLEVEL_INFO =     "INFO"
    private let _LOGLEVEL_DEBUG =    "DEBG"
    private let _LOGLEVEL_WARN =     "WARN"
    private let _LOGLEVEL_ERROR =    "ERRR"
    private let _LOGLEVEL_FATAL =    "FATL"
    
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
    
    //todo: this could be written a bit better, in that, SwiftLogger can still get to the private vars inside the thread protection
    /**Class that contains mutable properties that need to be guaranteed thread safety*/
    private class threadProtected {
        private var _currentLogTailLock = pthread_rwlock_t()
        private var _currentLogTail = ""
        var currentLogTail: String {
            get {
                var data = ""
                self._with(&self._currentLogTailLock) {
                    data = self._currentLogTail
                }
                return data
            }
            set {
                self._with_write(&self._currentLogTailLock) {
                    self._currentLogTail = newValue
                }
            }
        }
        
        private var _nextFileNumberLock = pthread_rwlock_t()
        private var _nextFileNumber: Int = 0
        var nextFileNumber: Int {
            get {
                var data = 0
                self._with(&self._nextFileNumberLock) {
                    data = self._nextFileNumber
                }
                return data
            }
            set {
                self._with_write(&self._nextFileNumberLock) {
                    self._nextFileNumber = newValue
                }
            }
        }
        
        init() {
            pthread_rwlock_init(&self._currentLogTailLock, nil)
            pthread_rwlock_init(&self._nextFileNumberLock, nil)
        }
        
        /**Thread safety method for accessing shared resource with multiple concurrent readers*/
        private func _with(rwlock: UnsafeMutablePointer<pthread_rwlock_t>, f: Void -> Void) {
            pthread_rwlock_rdlock(rwlock)
            f()
            pthread_rwlock_unlock(rwlock)
        }
        /**Thread safety method for mutating a shared resource with a single writer*/
        private func _with_write(rwlock: UnsafeMutablePointer<pthread_rwlock_t>, f: Void -> Void) {
            pthread_rwlock_wrlock(rwlock)
            f()
            pthread_rwlock_unlock(rwlock)
        }
    }
}