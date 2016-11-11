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
todo:
>test logging complex objects
>consider changing init to take in a class that will allow for easier construction
*/

import Foundation

enum SwiftLoggerGetLogsError: Error {
    /**Failed getting contents of logging directory*/
    case failedEnumeratingDirectory(error: Error)
}

/**Base class for the delegates*/
protocol SwiftLoggerDelegate {}
/**Delegate that provides information on file tasks*/
protocol SwiftLoggerFileDelegate: SwiftLoggerDelegate {
    /**
        Advises the delegate that a new file was created
        - Parameter fileName: The name of the file and path that was created
    */
    func swiftLogger(didCreateNewFile filePath: String)
}
/**Delegate that provides information on the log tail*/
protocol SwiftLoggerTailDelegate: SwiftLoggerDelegate {
    /**
        Advises the delegate that a message was written to the tail
        - Parameter message: The message that was written to the tail
    */
    func swiftLogger(didWriteLogToTail message: String)
}

open class SwiftLogger {
    /**Determines if logging can occur. This is set to false if problems were encountered during initialization*/
    var loggingIsActive: Bool = true
    
    /**NSFileManager singleton instance*/
    fileprivate let _fileManager: FileManager = FileManager.default
    /**Logging location*/
    fileprivate let _logPath: String
    /**The size of the tail before writing a disk, in bytes, this is effectively slightly smaller than the size of each file. Once the tail contains exactly or more bytes than specified here, it is written to a file.*/
    fileprivate let _fileSize: UInt
    /**The maximum size of storage for all logs, in bytes. If this value is set, the logger will start deleting older files, in favor of newer ones, when the maximum is met.*/
    fileprivate let _maxStorageSize: UInt64?
    /**Generates the name and file path for the next file that will be written to disk*/
    fileprivate var _nextFileName: String { get { return self._logPath + "/" + self._logFileNamePrefix + String(format: "%09d", self._protected.nextFileNumber) + ".txt" } }
    /**The prefix for files created by the logger*/
    fileprivate let _logFileNamePrefix: String = "log_"
    /**If true, logging messages are written to the standard output as well.*/
    fileprivate let _writeToStandardOutput: Bool
    /**The format to use when writing to the log*/
    fileprivate let _logFormat: String
    
    /*
    LOCKING
    */
    /**Contains mutable variables that need thread protection*/
    fileprivate let _protected = threadProtected()
    /**Mutex lock object for preventing read/write operations on log files from happening simultaneously*/
    fileprivate let _logFileLock = NSObject()
    
    /*
    DELEGATES
    */
    var fileDelegate: SwiftLoggerFileDelegate?
    var tailDelegate: SwiftLoggerTailDelegate?
    
    /**
        Creates an instance of the logger
    
        - Parameter delegate: A delegate to receive messages about what the logger is doing
        - Parameter alsoWriteToStandardOutput: if true, all log messages are also written to standard output (usually the debug area in Xcode)
        - Parameter directory: The directory in which to save log files. Defaults to `.applicationSupportDirectory`.
        - Parameter domain: The file system domain to search for the directory. Defaults to `.userDomainMask`.
        - Parameter explodeOnFailureToInit: If true, a fatal error will occur if the initialization fails. Defaults to true assuming that the application is dependent on logging. If this is not the case, simply supply false here, and only the standard output will be advise you that no logging will occur, denoted by "SWIFTLOGGER-NOLOG-MESSAGE".
        - Parameter fileSize: The size of the tail before writing to disk, in bytes, this is effectively the size of each file
        - Parameter logFormat: The format to use when logging. If nil, the default format is used. The following terms are recognized
            {level}     The log level
            {date}      The date the message was committed
            {time}      The time the message was committed
            {timezone}  The timezone of the date the message was committed
            {file}      The file name that the logging statement was called from (shortened to the last path component for brevity)
            {function}  The name and signature of the function that the logging statement was called from.
            {line}      The line of the file that the logging statement was called from.
    */
    init(
        delegate: SwiftLoggerDelegate? = nil,
        alsoWriteToStandardOutput: Bool = false,
        directory: FileManager.SearchPathDirectory = .applicationSupportDirectory,
        domain: FileManager.SearchPathDomainMask = .userDomainMask,
        explodeOnFailureToInit: Bool = true,
        fileSize: UInt = 1000,
        maxFileSize: UInt64? = nil,
        logFormat: String? = nil) {
        self.fileDelegate = delegate as? SwiftLoggerFileDelegate
        self.tailDelegate = delegate as? SwiftLoggerTailDelegate
        self._writeToStandardOutput = alsoWriteToStandardOutput
        self._fileSize = fileSize
        self._maxStorageSize = maxFileSize
        self._logFormat = logFormat ?? "{date} {time} {timezone} | {level} | {file}::{function}:{line} | "
        //create the logging directory
        let topDirectory: NSString = NSSearchPathForDirectoriesInDomains(directory, .userDomainMask, true).first! as NSString
        self._logPath = topDirectory.appendingPathComponent("SwiftLogger")
        if !self._fileManager.fileExists(atPath: self._logPath) {
            //it would be unfortunate if this blew up, but it will also tell you, immediately, that there's a config problem
            do {
                try self._fileManager.createDirectory(atPath: self._logPath, withIntermediateDirectories: true, attributes: nil)
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
        var lastFile: String?
        do {
            lastFile = try self._fileManager.contentsOfDirectory(atPath: self._logPath)
                .filter { $0.hasPrefix(self._logFileNamePrefix) }
                .sorted()
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
        if let lf = lastFile, lf != "" {
            let trimmed = lf
                .replacingOccurrences(of: self._logFileNamePrefix, with: "", options: [.caseInsensitive, .anchored])
                .replacingOccurrences(of: ".txt", with: "", options: [.caseInsensitive, .anchored, .backwards])
            if let n = Int(trimmed) {
                //don't append to this yet. we'll use the current file number until the filehandle is attached
                self._protected.nextFileNumber = n
            } else {
                debugPrint("SWIFTLOGGER", "failed parsing last log file number", lf, "trimmed", trimmed)
            }
        }
        
        if !self._fileManager.fileExists(atPath: self._nextFileName) {
            self._createNewFile(incrementFileNumberAfter: true)
        } else {
            self._attachFileHandle(self._nextFileName)
        }
    }
    
    deinit {
        self.shutdown()
        //we only truly want to close the file handle when the logger is de-referenced
        self._protected.fileHandle.closeFile()
    }
    
    /**
        INFO level log
        
        - Parameter message: A title or message for the log
        - Parameter object: A complex object or otherwise to add as contextual information for the log.
        - Parameter function: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the function and signature where this method was called from.
        - Parameter line: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the line number where this method was called from.
        - Parameter file: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the file this method was called from.
     */
    func info(_ message: String, _ object: Any? = nil, function: String = #function, line: Int = #line, file: String = #file) {
        self._parseEntry(self._LOGLEVEL_INFO, message: message, object: object, function: function, line: line, file: file)
    }
    /**
        DEBUG level log
     
     - Parameter message: A title or message for the log
     - Parameter object: A complex object or otherwise to add as contextual information for the log.
     - Parameter function: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the function and signature where this method was called from.
     - Parameter line: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the line number where this method was called from.
     - Parameter file: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the file this method was called from.
     */
    func debug(_ message: String, _ object: Any? = nil, function: String = #function, line: Int = #line, file: String = #file) {
        self._parseEntry(self._LOGLEVEL_DEBUG, message: message, object: object, function: function, line: line, file: file)
    }
    /**
        WARN level log
     
     - Parameter message: A title or message for the log
     - Parameter object: A complex object or otherwise to add as contextual information for the log.
     - Parameter function: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the function and signature where this method was called from.
     - Parameter line: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the line number where this method was called from.
     - Parameter file: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the file this method was called from.
     */
    func warn(_ message: String, _ object: Any? = nil, function: String = #function, line: Int = #line, file: String = #file) {
        self._parseEntry(self._LOGLEVEL_WARN, message: message, object: object, function: function, line: line, file: file)
    }
    /**
        ERROR level log
     
     - Parameter message: A title or message for the log
     - Parameter object: A complex object or otherwise to add as contextual information for the log.
     - Parameter function: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the function and signature where this method was called from.
     - Parameter line: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the line number where this method was called from.
     - Parameter file: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the file this method was called from.
     */
    func error(_ message: String, _ object: Any? = nil, function: String = #function, line: Int = #line, file: String = #file) {
        self._parseEntry(self._LOGLEVEL_ERROR, message: message, object: object, function: function, line: line, file: file)
    }
    /**
        FATAL level log
     
     - Parameter message: A title or message for the log
     - Parameter object: A complex object or otherwise to add as contextual information for the log.
     - Parameter function: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the function and signature where this method was called from.
     - Parameter line: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the line number where this method was called from.
     - Parameter file: DO NOT SUPPLY THIS ARGUMENT. This is filled automatically and will contain the name of the file this method was called from.
     */
    func fatal(_ message: String, _ object: Any? = nil, function: String = #function, line: Int = #line, file: String = #file) {
        self._parseEntry(self._LOGLEVEL_FATAL, message: message, object: object, function: function, line: line, file: file)
    }
    
    //todo: theres a potential to make this func public, so that you could set the log level programmatically, but i'm not sure how to force the coder to use one of the LOGLEVEL constants. i could just do a switch... but i feel like that's kinda lazy and might impact performance
    /**Middle function for logging, all general purpose logging functions filter into this function*/
    fileprivate func _parseEntry(_ logLevel: String, message: String, object: Any?, function: String, line: Int, file: String) {
        //before we process anything, get the time so know exactly when the logging occurred
        let timestamp = Date()
        let objectMessage: String?
        if let o = object {
            objectMessage = self._getMessageFromObject(o)
        } else {
            objectMessage = nil
        }
        self._formatAndWrite(logLevel, timestamp: timestamp, message: message, objectMessage: objectMessage, function: function, line: line, file: file)
    }
    
    fileprivate func _getMessageFromObject(_ o: Any) -> String {
        if let c = o as? CustomDebugStringConvertible {
            return c.debugDescription
        } else if let c = o as? CustomStringConvertible {
            return c.description
        } else if let c = o as? TextOutputStreamable {
            var targ = String()
            c.write(to: &targ)
            return targ
        } else {
            //if debugprint can, and i cant, well that sux and it needs to be figured out
            debugPrint("SWIFTLOGGER", "attempted to log your object, but it wasn't a conforming type!", o)
            return ""
        }
    }
    
    /**
        Prepares a message to be written by formatting it and then writes the formatted message to the log file.
    
        - Parameter logLevel: The log level for the batch of messages (_LOGLEVEL).
        - Parameter timestamp: The time at which the logger was called to process a logging event.
        - Parameter message: The literal message from the log.
        - Parameter objectMessage: The string version of an object provided at the top level of logging, or nil.
        - Parameter function: The name of the function the logging statement existed in.
        - Parameter line: The line of the file the logging statement existed in.
        - Parameter file: The path of the file the logging staement existed in.
    */
    fileprivate func _formatAndWrite(_ logLevel: String, timestamp: Date, message: String, objectMessage: String?, function: String, line: Int, file: String) {
        //get the last component of the file string for brevity
        let fileName: String
        if let n = file.components(separatedBy: "/").last {
            fileName = n
        } else {
            fileName = ""
        }
        var clean = self._logFormat
            .replacingOccurrences(of: "{level}", with: logLevel)
            .replacingOccurrences(of: "{date}", with: dateFormatters._date.string(from: timestamp))
            .replacingOccurrences(of: "{time}", with: dateFormatters._time.string(from: timestamp))
            .replacingOccurrences(of: "{timezone}", with: dateFormatters._zone.string(from: timestamp))
            .replacingOccurrences(of: "{function}", with: function)
            .replacingOccurrences(of: "{line}", with: String(line))
            .replacingOccurrences(of: "{file}", with: fileName)
        clean += message
        if let m = objectMessage {
            //todo: make an option for this separator?
            clean += " || " + m
        }
        self._write(clean)
    }
    
    /**Writes the message to the current file*/
    fileprivate func _write(_ message: String) {
        if !self.loggingIsActive {
            print("SWIFTLOGGER-NOLOG-MESSAGE", message)
            return
        }
        //add a new line to the end of the message
        let finalMessage = message + "\n"
        guard let messageData = finalMessage.data(using: String.Encoding.utf8) else {
            debugPrint("SWIFTLOGGER", "failed encoding log message to utf8", finalMessage)
            return
        }
        
        //todo: opportunity here to send this off to background thread. perf testing shows that this isn't necessary, 
        //but if you log something crazy huge, it could take a while... maybe add a 1MB message write perf test to see if we really want to go that far.
        
        //thread-safety: make sure this is only ever called once at a time, and only one of reading/writing logs should ever be executing at once
        objc_sync_enter(self._logFileLock)
        //write to the file
        self._protected.fileHandle.write(messageData)
        objc_sync_exit(self._logFileLock)
        
        //write the message to output if needed
        if self._writeToStandardOutput {
            print(message)
        }
        
        //let the delegate know it's been written
        self.tailDelegate?.swiftLogger(didWriteLogToTail: message)
        
        //check if we need to create a new file
        //lock out the file before we do this, just in case some other thread pushed us over the limit and created a new file
        objc_sync_enter(self._logFileLock)
        if UInt(self._protected.fileHandle.availableData.count) > self._fileSize {
            self._createNewFile()
        }
        objc_sync_exit(self._logFileLock)
    }
    
    /** 
        Creates a new file and resets the filehandle to point to it
        
        - Parameter incrementFileNumberAfter: Increments the next file marker AFTER creating the file.
     */
    fileprivate func _createNewFile(incrementFileNumberAfter: Bool = false) {
        //update the next file number and create the file
        if !incrementFileNumberAfter {
            self._protected.nextFileNumber += 1
        } else {
            defer { self._protected.nextFileNumber += 1 }
        }
        //make sure the file doesn't already exist.
        if !self._fileManager.fileExists(atPath: self._nextFileName) {
            guard self._fileManager.createFile(atPath: self._nextFileName, contents: nil, attributes: nil) else {
                debugPrint("SWIFTLOGGER", "failed to create new file. will continue to use current file", self._nextFileName)
                return
            }
        }
        debugPrint("SWIFTLOGGER", "created file at path", self._nextFileName)
        //if we have a file delegate, let them know we have a new file
        self.fileDelegate?.swiftLogger(didCreateNewFile: self._nextFileName)
        self._attachFileHandle(nil)
        //apply our storage limit
        self._applyStorageLimit()
    }
    
    /** 
        Attaches the files handler to the file
        - Parameter filePath: The path to the file to attach the filehandle to. If nil, the filehandle is attached to `self._nextFileName`
     */
    fileprivate func _attachFileHandle(_ filePath: String?) {
        //close the filehandle and reopen it on the new file
        self._protected.fileHandle.synchronizeFile()
        self._protected.fileHandle.closeFile()
        self._protected.fileHandle = FileHandle(forUpdatingAtPath: filePath ?? self._nextFileName)!
    }
    
    /**Checks if the maximum storage limit has been reached, and if so, deletes old files*/
    fileprivate func _applyStorageLimit() {
        //todo: now that we have this, create a new delegate that hooks into files we're about to delete
        //todo: might need to change delegate to list<delegates>. a user might want to have separate implementations, not one delegate that implements everything they want
        //no max storage size? dont do anything
        guard let max = self._maxStorageSize else {
            return
        }
        //get all the logs and check the content size
        guard let logFiles = try? self._getLogFileNames() else {
            debugPrint("SWIFTLOGGER", "attempted to apply storage limit, but couldn't get file names")
            return
        }
        //combination of filename and size so we can decide how many and which files to delete
        var sizes = [String:UInt64]()
        //thread-safety: make sure this is only ever called once at a time, and only one of reading/writing logs should ever be executing at once
        objc_sync_enter(self._logFileLock)
        for file in logFiles {
            let attributes: [FileAttributeKey:Any]
            do {
                attributes = try self._fileManager.attributesOfItem(atPath: self._logPath + "/" + file)
            } catch {
                debugPrint("SWIFTLOGGER", "failed getting file attributes to check size", error)
                continue
            }
            if let size = attributes[FileAttributeKey.size] as? UInt64 {
                sizes[file] = size
            }
        }
        objc_sync_exit(self._logFileLock)
        //get the overflow which will tell us how many to kill
        var overflow = sizes.values.reduce(0,+) - max
        var fileIndexToDelete = 0
        while overflow > 0 && fileIndexToDelete < logFiles.count {
            //delete a file, one a time, until we don't have an overflow
            let fileName = logFiles[fileIndexToDelete]
            //thread-safety: make sure this is only ever called once at a time, and only one of reading/writing logs should ever be executing at once
            objc_sync_enter(self._logFileLock)
            defer { objc_sync_exit(self._logFileLock) }
            do {
                try self._fileManager.removeItem(atPath: self._logPath + "/" + fileName)
                overflow -= sizes[fileName]!
                fileIndexToDelete += 1
            } catch {
                debugPrint("SWIFTLOGGER", "failed deleting file to maintain file limit")
            }
        }
    }
    
    /**
        Gets all log files.
    
        - Returns: a dictionary containing the name of the file as the key and the actual contents as the value.
        - Throws: `SwiftLoggerGetLogsError.FailedEnumeratingDirectory(ErrorType)` if there was an issue getting the contents of the logging directory, includes the error thrown by the file manager.
    */
    func getLogs() throws -> [String:String] {
        if !self.loggingIsActive {
            debugPrint("SWIFTLOGGER-NOLOG", "attempted to get logs but logging is inactive")
            return [String:String]()
        }
        var logs = [String:String]()
        //bubble up the exception if one is thrown
        let files = try self._getLogFileNames()
        //thread-safety: make sure this is only ever called once at a time, and only one of reading/writing logs should ever be executing at once
        objc_sync_enter(self._logFileLock)
        defer { objc_sync_exit(self._logFileLock) }
        for file in files {
            guard let dataContents = self._fileManager.contents(atPath: self._logPath + "/" + file) else {
                debugPrint("SWIFTLOGGER", "failed getting contents of file at path", self._logPath, file)
                continue
            }
            guard let contents = String(data: dataContents, encoding: String.Encoding.utf8) else {
                debugPrint("SWIFTLOGGER", "failed encoding data to utf8", self._logPath, file)
                continue
            }
            logs[file] = contents
        }
        return logs
    }
    
    /**
        Gets the names of all logs files, in order of creation
     
        - Throws: `SwiftLoggerGetLogsError.FailedEnumeratingDirectory(ErrorType)` if there was an issue getting the contents of the logging directory, includes the error thrown by the file manager.
     */
    fileprivate func _getLogFileNames() throws -> [String] {
        //thread-safety: make sure this is only ever called once at a time, and only one of reading/writing logs should ever be executing at once
        objc_sync_enter(self._logFileLock)
        defer { objc_sync_exit(self._logFileLock) }
        do {
            return try self._fileManager.contentsOfDirectory(atPath: self._logPath)
                .filter { $0.hasPrefix(self._logFileNamePrefix) }
                .sorted()
        } catch {
            debugPrint("SWIFTLOGGER", "failed getting contents of logging directory", self._logPath, error)
            throw SwiftLoggerGetLogsError.failedEnumeratingDirectory(error: error)
        }
    }
    
    /**
        Purges log files
    
        Generally, you only really need to purge specific files if you're pulling files out to consume them while the application is still potentially logging. This prevents you from purging files that were created during the time your application was consuming the pulled files.
    
        - Parameter filesToPurge: a list of file names to purge, usually provided by the `getLogs()` function. All logs are purged if nil is passed
    */
    func purgeLogs(_ filesToPurge: [String]?) {
        if !self.loggingIsActive {
            return
        }
        //thread-safety: make sure this is only ever called once at a time, and only one of reading/writing logs should ever be executing at once
        objc_sync_enter(self._logFileLock)
        defer { objc_sync_exit(self._logFileLock) }
        let files: [String]
        if filesToPurge != nil {
            files = filesToPurge!
        } else {
            do {
                files = try self._fileManager.contentsOfDirectory(atPath: self._logPath)
                    .filter { $0.hasPrefix(self._logFileNamePrefix) }
            } catch {
                debugPrint("SWIFTLOGGER", "failed getting contents of logging directory for purge", self._logPath, error)
                return
            }
        }
        for file in files {
            let fileName = self._logPath + "/" + file
            if !self._fileManager.fileExists(atPath: fileName) {
                return
            }
            do {
                try self._fileManager.removeItem(atPath: fileName)
            } catch {
                debugPrint("SWIFTLOGGER", "failed purging file at path", self._logPath, "filename", file)
            }
        }
    }
    
    /**
        Guarantees all log data is flushed to disk.
    */
    func shutdown() {
        self._protected.fileHandle.synchronizeFile()
    }
    
    // MARK - utilities
    //log levels. you might be asking... why ERRR and FATL? it's because im kinda OCD about how the log looks and this makes everything line up vertically.
    fileprivate let _LOGLEVEL_INFO =     "INFO"
    fileprivate let _LOGLEVEL_DEBUG =    "DEBG"
    fileprivate let _LOGLEVEL_WARN =     "WARN"
    fileprivate let _LOGLEVEL_ERROR =    "ERRR"
    fileprivate let _LOGLEVEL_FATAL =    "FATL"
    
    fileprivate class dateFormatters: DateFormatter {
        init(_ format: String) {
            super.init()
            self.dateFormat = format
        }
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        /**default logging format: 01/20/16 12:34:56.789 PDT **/
        fileprivate static let _default = dateFormatters("MM/dd/yy HH:mm:ss.SSS zzz")
        fileprivate static let _date = dateFormatters("MM/dd/yy")
        fileprivate static let _time = dateFormatters("HH:mm:ss.SSS")
        fileprivate static let _zone = dateFormatters("zzz")
    }
    
    /**Class that contains mutable properties that need to be guaranteed thread safety*/
    fileprivate class threadProtected {
        private var _currentLogTailLock = pthread_rwlock_t()
        private var _currentLogTail = ""
        fileprivate var currentLogTail: String {
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
        fileprivate var nextFileNumber: Int {
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
        
        private var _fileHandleLock = pthread_rwlock_t()
        private var _fileHandle = FileHandle()
        fileprivate var fileHandle: FileHandle {
            get {
                var handle: FileHandle? = nil
                self._with(&self._fileHandleLock) {
                    handle = self._fileHandle
                }
                return handle ?? FileHandle()
            }
            set {
                self._with_write(&self._fileHandleLock) {
                    self._fileHandle = newValue
                }
            }
        }
        
        init() {
            pthread_rwlock_init(&self._currentLogTailLock, nil)
            pthread_rwlock_init(&self._nextFileNumberLock, nil)
            pthread_rwlock_init(&self._fileHandleLock, nil)
        }
        
        /**Thread safety method for accessing shared resource with multiple concurrent readers*/
        private func _with(_ rwlock: UnsafeMutablePointer<pthread_rwlock_t>, f: (Void) -> Void) {
            pthread_rwlock_rdlock(rwlock)
            f()
            pthread_rwlock_unlock(rwlock)
        }
        /**Thread safety method for mutating a shared resource with a single writer*/
        private func _with_write(_ rwlock: UnsafeMutablePointer<pthread_rwlock_t>, f: (Void) -> Void) {
            pthread_rwlock_wrlock(rwlock)
            f()
            pthread_rwlock_unlock(rwlock)
        }
    }
}
