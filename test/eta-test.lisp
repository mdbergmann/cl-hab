(defpackage :cl-eta.eta-test
  (:use :cl :fiveam :cl-mock :cl-eta.eta :eta-ser-if)
  (:export #:run!
           #:all-tests
           #:nil))
(in-package :cl-eta.eta-test)

(def-suite eta-tests
  :description "ETA tests"
  :in cl-eta.tests:test-suite)

(in-suite eta-tests)

(defparameter *open-serial-called* nil)
(defparameter *write-serial-called* nil)
(defparameter *read-serial-called* 0)
(defparameter *eta-col-called* 0)
(defparameter *eta-col-no-complete* #())

(defclass fake-serial-proxy (eta-ser-if:serial-proxy) ())
(defmethod eta-ser-if:open-serial ((proxy fake-serial-proxy) device)
  (assert proxy)
  (cond
    ((string= "/dev/not-exists" device) (error "Can't open!"))
    (t (setf *open-serial-called* t))))
(defmethod eta-ser-if:write-serial ((proxy fake-serial-proxy) port data)  
  (declare (ignore port data))
  (assert proxy)
  (setf *write-serial-called* 5))
(defmethod eta-ser-if:read-serial ((proxy fake-serial-proxy) port &optional timeout)
  (declare (ignore port timeout))
  ;; we just do a tiny timeout
  (sleep .1)
  (incf *read-serial-called*)
  #())

(defmethod eta-col:collect-data ((impl (eql :test)) prev-data new-data)
  (incf *eta-col-called*)
  (values nil (concatenate 'vector prev-data new-data)))

(defmethod eta-col:collect-data ((impl (eql :test-no-complete-pkg)) prev-data new-data)
  (declare (ignore new-data))
  (setf *eta-col-no-complete* (concatenate 'vector prev-data `#(,*eta-col-called*)))
  (incf *eta-col-called*)
  (values nil *eta-col-no-complete*))

(def-fixture init-destroy ()
  (setf *open-serial-called* nil
        *write-serial-called* nil
        *read-serial-called* 0
        *eta-col-called* 0
        *eta-col-no-complete* #())
  (unwind-protect
       (progn
         (eta:ensure-initialized)
         (change-class eta:*serial-proxy* 'fake-serial-proxy)
         (&body))
    (eta:ensure-shutdown)))
  
(test init-serial
  (with-fixture init-destroy ()
    (is (eq :ok (init-serial "/dev/serial")))
    (is-true *open-serial-called*)))

(test init-serial--fail-to-open
  (with-fixture init-destroy ()
    (let ((init-serial-result (multiple-value-list (init-serial "/dev/not-exists"))))
      (is (eq :fail (car init-serial-result)))
      (is (string= "Can't open!" (cadr init-serial-result))))))

(test start-record--serial-written
  "Tests that the write function on the serial proxy is called.
This is asynchronous and we don't check a result.
A result will be visible when this function is called on the REPL."
  (with-fixture init-destroy ()
    (is (eq :ok (start-record)))
    (is-true (utils:assert-cond
              (lambda () (= 5 *write-serial-called*))
              1.0))))

(test start-record--serial-written--read-received
  (with-fixture init-destroy ()
    (is (eq :ok (start-record)))
    (is-true (utils:assert-cond
              (lambda () (> *read-serial-called* 1))
              1.0))))

(test start-record--read-received--call-parser
  (with-fixture init-destroy ()
    (setf eta:*eta-collector* :test)
    (is (eq :ok (start-record)))
    (is-true (utils:assert-cond
              (lambda () (and (> *read-serial-called* 0)
                         (> *eta-col-called* 0)))
              1.0))))

(test start-record--read-received--call-parser--no-complete
  "Continue loop"
  (with-fixture init-destroy ()
    (setf eta:*eta-collector* :test-no-complete-pkg)
    (is (eq :ok (start-record)))
    (is-true (utils:assert-cond
              (lambda () (and (> *read-serial-called* 0)
                         (> *eta-col-called* 4)))
              1.0))
    (format t "col-final: ~a~%" *eta-col-no-complete*)
    (is (equalp *eta-col-no-complete* (coerce (loop :for x :from 1 :to (1- *eta-col-called*)
                                                    :collect x)
                                              'vector)))))


#|
TODO:
OK - test for read continously
=> - test for call to read handler when data arrived
- test 'start-record' actually sends the proper ETA package
- 'stop-record'
- 'shutdown-serial
|#
