//
//  IOU.swift
//  IOU
//
//  Created by Grant on 6/11/15.
//  Copyright (c) 2015 Oladipo.us. All rights reserved.
//

import Foundation

// MARK: - IOUState

private enum IOUState {
    case Pending, Rejected, Resolved
}

// MARK: - IOU

class IOU<T> {
    
    private var error: ErrorType?
    private var value: T? = nil
    private var state: IOUState = .Pending
    private var onErrorObservers: [((ErrorType) -> Void, dispatch_queue_t?)] = []
    private var onValueObservers: [((T) -> Void, dispatch_queue_t?)] = []
    
    private lazy var serialQueue: dispatch_queue_t = {
        return dispatch_queue_create("us.oladipo.iou", DISPATCH_QUEUE_SERIAL)
    }()
    
    // MARK:- Reject
    
    func onError(observer: (ErrorType) -> Void) -> IOU<T> {
        return self.onError(nil, observer: observer)
    }
    
    func onError(queue: dispatch_queue_t?, observer: (ErrorType) -> Void) -> IOU<T> {
        let observers = self.onErrorObservers + [(observer, queue)]
        self.onErrorObservers = observers
        
        if self.state != .Pending {
            self.callAndRemoveObservers()
        }
        
        return self
    }
    
    private func reject(error: ErrorType) {
        self.updateState(.Rejected, value: nil, error: error)
        self.callAndRemoveObservers()
    }
    
    // MARK:- Resolve
    
    func onValue(observer: (T) -> Void) -> IOU<T> {
        return self.onValue(nil, observer: observer)
    }
    
    func onValue(queue: dispatch_queue_t?, observer: (T) -> Void) -> IOU<T> {
        let observers = self.onValueObservers + [(observer, queue)]
        self.onValueObservers = observers
        
        if self.state != .Pending {
            self.callAndRemoveObservers()
        }
        
        return self
    }
    
    private func resolve(value: T) {
        self.updateState(.Resolved, value: value, error: nil)
        self.callAndRemoveObservers()
    }
    
    // MARK:- Transform
    
    func transform<U>(transform: (T) throws -> U) -> IOU<U> {
        return self.transform(nil, transform: transform)
    }
    
    func transform<U>(queue: dispatch_queue_t?, transform: (T) throws -> U) -> IOU<U> {
        return self.transform(queue, valueTransform: transform) { error in error }
    }
    
    func transform<U>(queue: dispatch_queue_t?, valueTransform: (T) throws -> U, errorTransform: (ErrorType) throws -> ErrorType) -> IOU<U> {
        let handler = IOUHandler<U>()
        
        self.onError(queue) { error in
            do {
                let newError = try errorTransform(error)
                handler.reject(newError)
            } catch let tError {
                handler.reject(tError)
            }
        }
        
        self.onValue(queue) { value in
            do {
                let newValue = try valueTransform(value)
                handler.resolve(newValue)
            } catch let error {
                handler.reject(error)
            }
        }
        
        return handler.iou
    }
    
    // MARK: Updating state
    
    private func updateState(state: IOUState, value: T?, error: ErrorType?) {
        dispatch_sync(self.serialQueue) {
            if self.state == .Pending {
                self.state = state
                
                if let uValue = value {
                    self.value = uValue
                } else if let uError = error {
                    self.error = uError
                }
            }
        }
    }
    
    private func callAndRemoveObservers() {
        if self.state == .Resolved {
            for (observer, queue) in self.onValueObservers {
                
                let closure = {
                    observer(self.value!)
                }
                
                if let uQueue = queue {
                    dispatch_async(uQueue, closure)
                } else {
                    closure()
                }
            }
        } else if self.state == .Rejected {
            for (observer, queue) in self.onErrorObservers {
                
                let closure = {
                    observer(self.error!)
                }
                
                if let uQueue = queue {
                    dispatch_async(uQueue, closure)
                } else {
                    closure()
                }
            }
        }
        
        self.onErrorObservers = []
        self.onValueObservers = []
        
    }
}

// MARK: - IOUHandler

public struct IOUHandler<T> {
    let iou:IOU<T>
    
    public init() {
        self.iou = IOU<T>()
    }
    
    func reject(error: ErrorType) {
        self.reject(error, queue: nil)
    }
    
    func reject(error: ErrorType, queue: dispatch_queue_t?) {

        let closure = {
            self.iou.reject(error)
        }
        
        if let uQueue = queue {
            dispatch_async(uQueue, closure)
        } else {
            closure()
        }
    }
    
    func resolve(value: T) {
        self.resolve(value, queue: nil)
    }
    
    func resolve(value: T, queue: dispatch_queue_t?) {

        let closure = {
            self.iou.resolve(value)
        }

        if let uQueue = queue {
            dispatch_async(uQueue, closure)
        } else {
            closure()
        }
    }
}
