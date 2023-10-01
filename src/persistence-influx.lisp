(defpackage :cl-hab.influx-persistence
  (:use :cl :cl-hab.persistence)
  (:nicknames :influx-persistence)
  (:import-from #:persp
                #:persistence)
  (:export #:influx-persistence
           #:make-influx-persistence)
  )

(in-package :cl-hab.influx-persistence)

(defclass influx-persistence (persistence)
  ((base-url :initform nil
             :reader base-url)
   (token :initform nil
          :reader token)
   (org :initform nil
        :reader org)
   (bucket :initform nil
           :reader bucket)
   (precision :initform nil
              :reader precision)))

(defun make-influx-persistence (id &key
                                     base-url
                                     token
                                     org
                                     bucket)
  (persp::make-persistence id
                           :type 'influx-persistence
                           :base-url base-url
                           :token token
                           :org org
                           :bucket bucket))

(defmethod act:pre-start ((persistence influx-persistence))
  (log:debug "Pre-starting persistence: ~a" persistence)
  (let ((other-args (act:other-init-args persistence)))
    (log:debug "Other args: ~a" other-args)
    (when other-args
      (with-slots (base-url token org bucket precision) persistence
        (setf base-url (getf other-args :base-url)
              token (getf other-args :token)
              org (getf other-args :org)
              bucket (getf other-args :bucket)
              precision "s"))))
  (call-next-method))

(defmethod initialize ((persistence influx-persistence))
  (log:info "Initializing persistence: ~a" persistence))

(defmethod shutdown ((persistence influx-persistence))
  (log:info "Shutting down persistence: ~a" persistence))

(defmethod persist ((persistence influx-persistence) item)
  (log:debug "Persisting, item: ~a" item)
  (let* ((item-name (act-cell:name item))
         (item-state (item:get-item-stateq item))
         (item-value (item:item-state-value item-state))
         (item-timestamp (local-time:universal-to-timestamp
                          (item:item-state-timestamp item-state))))
    (multiple-value-bind (body status headers)
        (drakma:http-request (format nil "~a/api/v2/write" (base-url persistence))
                             :method :post
                             :parameters `(("bucket" . ,(bucket persistence))
                                           ("org" . ,(org persistence))
                                           ("precision" . ,(precision persistence)))
                             :accept "application/json"
                             :additional-headers
                             `(("Authorization" . ,(format nil "Token ~a" (token persistence))))
                             :content-type "text/plain; charset=utf-8"
                             :content (format nil "~a,item=~a value=\"~a\" ~a"
                                              item-name item-name item-value
                                              (local-time:timestamp-to-unix item-timestamp)))
      (case status
        (204 (log:info "Persisted item OK: ~a" item))
        (t
         (progn
           (log:warn "Failed to persist item: ~a" item)
           (log:warn "Response: ~a" (babel:octets-to-string body))
           (log:warn "Status: ~a" status)
           (log:warn "Headers: ~a" headers)))))))

(defmethod retrieve ((persistence influx-persistence) item)
  "Output format of influxdb is csv, so we need to parse it."
  (log:debug "Reading item: ~a" item)
  (let ((item-name (act-cell:name item)))
    (multiple-value-bind (body status headers)
        (drakma:http-request "http://picellar:8086/api/v2/query"
                             :method :post
                             :parameters `(("org" . ,(org persistence)))
                             :accept "application/json"
                             :additional-headers
                             `(("Authorization" . ,(format nil "Token ~a" (token persistence))))
                             :content-type "application/vnd.flux"
                             :content 
                             (format nil "from(bucket:\"~a\")
|> range(start: 0)
|> filter(fn: (r) => r._measurement == \"~a\")
|> last()" (bucket persistence) item-name))
      (case status
        (200
         (progn
           (log:info "Read item OK: ~a" item)
           (let* ((csv-lines (str:split (format nil "~C~C" #\return #\linefeed) body))
                  (csv-columns
                    (mapcar (lambda (s) (str:split "," s :omit-nulls t))
                            csv-lines))
                  (header-val-pairs
                    (mapcar #'list (first csv-columns) (second csv-columns))))
             (let ((timestamp
                     (find "_time" header-val-pairs :test #'equal :key #'car))
                   (value
                     (find "_value" header-val-pairs :test #'equal :key #'car)))
               (make-persisted-item
                :value (second value)
                :timestamp (local-time:timestamp-to-universal
                            (local-time:parse-timestring (second timestamp))))))))
        (t
         (progn
           (log:warn "Failed to read item: ~a" item)
           (log:warn "Response: ~a" (babel:octets-to-string body))
           (log:warn "Status: ~a" status)
           (log:warn "Headers: ~a" headers)
           nil))))))
