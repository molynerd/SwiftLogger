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

todo:
>async
>file writing
>file reading
>create a delegate that responds to events like "tailFlushedToDisk, logWrittenToTail" and others, in case someone wants to hook into the events and fire off the bug report automatically
>figure out how to call a method on application exit/crash etc so we can flush the tail
>write some stuff to the log on startup? maybe as a diagnostics setting?
*/

import Foundation

public class SwiftLogger {
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
    /**The prefix for files created by the logger*/
    private let _logFileNamePrefix: String = "log_"
    //todo: implement this so we can prevent crashing later and switch to debug logging
    /**Determines if logging can occur. This is set to false if problems were encountered during initialization*/
    private var _canLog: Bool = true
    
    /**
        Creates an instance of the logger
    
        - Parameter directory: The directory in which to save log files. Defaults to `.ApplicationSupportDirectory`.
        - Parameter domain: The file system domain to search for the directory. Defaults to `.UserDomainMask`.
        - Parameter explodeOnFailureToInit: If true, a fatal error will occur if the initialization fails. Defaults to true assuming that the application is dependent on logging. If this is not the case, simply use false here, and only `debugPrint` will be advise you that no logging will occur.
        - Parameter fileSize: The size of the tail before writing a disk, in bytes, this is effectively the size of each file
    */
    init(
        directory: NSSearchPathDirectory = .ApplicationSupportDirectory,
        domain: NSSearchPathDomainMask = .UserDomainMask,
        explodeOnFailureToInit: Bool = true,
        fileSize: Int = 1000) {
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
                        self._canLog = false
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
                    self._canLog = false
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
        self._formatAndWrite(.Info, timestamp: timestamp, messages: messages)
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
    
        - Parameter logLevel: The log level for the batch of messages.
        - Parameter timestamp: The time at which the logger was called to process a logging event.
        - Parameter messages: The unformatted messages to log.
    */
    private func _formatAndWrite(logLevel: LogLevelTypes, timestamp: NSDate, messages: [String]) {
        /*EXPECTED FORMAT
        INFO:01/23/16 13:45:123456 PDT
        >this is the first in the batch
        >this is the second in the batch
        ERROR:01/23/16 13:45:123456 PDT
        >this is the next one but it's an error
        */
        var clean = "\(logLevel.label):\(dateFormatters._default.stringFromDate(timestamp))\n"
        clean += messages.map { ">\($0)" }.joinWithSeparator("\n")
        self._write(clean)
    }
    
    /**
        Writes the message to the current tail
    */
    private func _write(message: String) {
        //append to the log
        //if there's already stuff in the tail, slap a line break in there to break up the messages
        if self._currentLogTail != "" {
            self._currentLogTail += "\n" + message
        } else {
            self._currentLogTail += message
        }
        //check if we need to flush to disk
        if self._fileSize < self._currentLogTail.utf8.count {
            self.flushTailToDisk()
        }
    }
    
    /**
        Flushes the tail to a file on the disk. Call this directly if the application is about to crash or any other reason you want to guarantee the log info is hardened.
    */
    func flushTailToDisk() {
        //todo: figure out how to do a mutex lock on this method so that we can prevent clobbering
        if self._currentLogTail == "" {
            return
        }
        //todo: figure out how to format the number so we have log_000001.txt
        let finalPath = self._logPath.stringByAppendingString("/\(self._logFileNamePrefix)\(self._nextFileNumber).txt")
        debugPrint("SWIFTLOGGER", "final write path", finalPath)
        //todo: use writeToFile or filemanager? probably filemanager since the other is deprecated. wait, this doesnt appear to be deprecated...
        do {
            try self._currentLogTail.writeToFile(finalPath, atomically: true, encoding: NSUTF8StringEncoding)
            self._currentLogTail = ""
            self._nextFileNumber += 1
        } catch {
            debugPrint("SWIFTLOGGER", "failed attempting to write file to a path", error)
        }
    }
    
    //todo: throw for errors retrieving files? not sure a user would want to handle that. i think i would
    /**
        Gets all log files.
    
        - Returns: a dictionary containing the name of the file as the key and the actual contents as the value. nil is returned if there was a problem getting the files.
    */
    func getLogs() -> [String:String]? {
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
    
    //todo: consider changing this to constants, since we aren't using any other enum functionality
    private enum LogLevelTypes {
        case Info
        case Debug
        case Warn
        case Error
        case Fatal
        
        var label: String {
            get {
                switch self {
                case Info:  return "INFO"
                case Debug: return "DEBG"
                case Warn:  return "WARN"
                case Error: return "ERRR"
                case Fatal: return "FATL"
                }
            }
        }
    }
}

