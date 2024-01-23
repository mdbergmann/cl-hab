(defpackage :chipi-web.token-store-test
  (:use :cl :endecode :fiveam :cl-mock :chipi-web.token-store)
  (:export #:run!
           #:all-tests
           #:nil))
(in-package :chipi-web.token-store-test)

(def-suite token-store-tests
  :description "Tests for token store - memory backend"
  :in chipi-web.tests:test-suite)

(in-suite token-store-tests)

(def-fixture mem-backend ()
  (unwind-protect
       (progn
         (setf *token-store-backend* *memory-backend*)
         (&body))
    (setf *token-store-backend* nil)))

(test create-token
  (with-fixture mem-backend ()
    (with-mocks ()
      (answer token-store::store-token t)
      (let ((token-id (create-token "username")))
        (is-true token-id)
        (is (> (length token-id) 0))
        (is (stringp token-id))
        (is-true (base64-string-to-octets token-id t)))
      (is (= (length (invocations 'token-store::store-token)) 1)))))

(test read-token
  (with-fixture mem-backend ()
    (with-mocks ()
      (answer token-store::retrieve-token
        (make-instance 'token
                       :user-id "username"
                       :token-id "token-id"))
      (let ((token (read-token "token-id")))
        (is (= (length (invocations 'token-store::retrieve-token)) 1))
        (is-true (typep token 'token))
        (is (string= (token-id token) "token-id"))
        (is (string= (user-id token) "username"))
        (is (integerp (expiry token)))))))

(test revoke-token--existing
  (with-fixture mem-backend ()
    (with-mocks ()
      (answer token-store::delete-token t)
      (is-true (revoke-token "token-id"))
      (is (= (length (invocations 'token-store::delete-token)) 1)))))

(test revoke-token--not-existing
  (with-fixture mem-backend ()
    (with-mocks ()
      (answer token-store::delete-token nil)
      (is-false (revoke-token "token-id"))
      (is (= (length (invocations 'token-store::delete-token)) 1)))))

(test token-expired--delete-when-expired
  (with-fixture mem-backend ()
    (with-mocks ()
      (answer token-store::retrieve-token
        (make-instance 'token
                       :user-id "username"
                       :token-id "token-id"
                       :expiry (- (get-universal-time) 1)))
      (answer token-store::delete-token t)
      (is-true (expired-token-p "token-id"))
      (is (= (length (invocations 'token-store::delete-token)) 1)))))

(test token-not-expired
  (with-fixture mem-backend ()
    (with-mocks ()
      (answer token-store::retrieve-token
        (make-instance 'token
                       :user-id "username"
                       :token-id "token-id"))
      (is-false (expired-token-p "token-id")))))

(test token-exists
  (with-fixture mem-backend ()
    (with-mocks ()
      (answer token-store::retrieve-token
        (make-instance 'token
                       :user-id "username"
                       :token-id "token-id"))
      (is-true (exists-token-p "token-id")))))

(test token-not-exists
  (with-fixture mem-backend ()
    (with-mocks ()
      (answer token-store::retrieve-token nil)
      (is-false (exists-token-p "token-id")))))
