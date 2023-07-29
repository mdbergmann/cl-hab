(defpackage :cl-hab.simple-persistence
  (:use :cl :cl-hab.persistence)
  (:nicknames :simple-persistence)
  (:import-from #:persp
                #:persistence)
  (:export #:simple-persistence
           #:make-simple-persistence))

(in-package :cl-hab.simple-persistence)

(defclass simple-persistence (persistence)
  ((storage-root-path :initform #P""
                      :documentation "The root path where item values are stored.")))

(defun make-simple-persistence (id &key storage-root-path)
  (persp::make-persistence id
                           :type 'simple-persistence
                           :storage-root-path storage-root-path))

(defmethod act:pre-start ((persistence simple-persistence))
  (log:debug "Pre-starting persistence: ~a" persistence)
  (let ((other-args (act:other-init-args persistence)))
    (log:debug "Other args: ~a" other-args)
    (when other-args
      (setf (slot-value persistence 'storage-root-path)
            (uiop:ensure-directory-pathname
             (getf other-args :storage-root-path #P"")))))
  (call-next-method))

(defmethod initialize ((persistence simple-persistence))
  (log:debug "Initializing persistence: ~a" persistence)
  (with-slots (storage-root-path) persistence
    (uiop:ensure-all-directories-exist (list storage-root-path))))

(defmethod shutdown ((persistence simple-persistence))
  (log:debug "Shutting down persistence: ~a" persistence))

(defmethod persist ((persistence simple-persistence) item value)
  (with-slots (storage-root-path) persistence
    (let ((path (merge-pathnames (format nil "~a.store" (act-cell:name item))
                                 storage-root-path)))
      (log:debug "Persisting to file: ~a, item: ~a" path item)
      (with-open-file (stream path
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (print value stream)))))

(defmethod retrieve ((persistence simple-persistence) item)
  (with-slots (storage-root-path) persistence
    (let ((path (merge-pathnames (format nil "~a.store" (act-cell:name item))
                                 storage-root-path)))
      (log:debug "Reading from file: ~a, item: ~a" path item)
      (with-open-file (stream path)
        (read stream)))))
