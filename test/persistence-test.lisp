(defpackage :cl-hab.persistence-test
  (:use :cl :fiveam :cl-hab.persistence)
  (:export #:run!
           #:all-tests
           #:nil))
(in-package :cl-hab.persistence-test)

(def-suite persistence-tests
  :description "Persistence tests"
  :in cl-hab.tests:test-suite)

(in-suite persistence-tests)

