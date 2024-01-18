(defpackage :chipi-web.user-store
  (:use :cl)
  (:nicknames :user-store)
  (:export #:user
           #:find-user-by-username
           #:verify-password))

(in-package :chipi-web.user-store)

(defvar *scrypt-salt* (babel:string-to-octets "my-awefully-secure-salt"))
(defvar *user*
  (let ((store (make-hash-table :test #'equal)))
    (setf (gethash "admin" store)
          (make-user "admin" "admin"))
    store))

(defclass user ()
  ((username :initarg :username :accessor username)
   (password :initarg :password :accessor password)))

(defun make-user (username password)
  (let ((hashed-pw (cryp:scrypt-data
                    (babel:string-to-octets password)
                    *scrypt-salt*)))
    (make-instance 'user :username username
                         :password hashed-pw)))

(defun find-user-by-username (username)
  "Not implemented")

(defun verify-password (user password)
  "Not implemented")
