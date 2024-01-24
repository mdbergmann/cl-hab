(defpackage :chipi.env
  (:use :cl)
  (:nicknames :envi)
  (:export #:ensure-env
           #:shutdown-env
           #:ensure-runtime-dir))

(in-package :chipi.env)

(defvar *rel-runtime-dir* "runtime/"
  "The relative path to the root runtime directory for chipi.")

(defun ensure-runtime-dir (&optional (dir nil))
  "Ensure that the runtime directory exists.
This is called as part of `ensure-env' but can be called separately.
If DIR is not specified, the root runtime folder is ensured.
Otherwise, the relative path DIR is ensured.
Returns the absolute path to the ensured directory.

It is possible to override the relative root runtime directory by:

```
(let ((*rel-runtime-dir* \"test-runtime/\"))
  (ensure-runtime-dir))
```

But note that the runtime dir will be computed on each call to `ensure-runtime-dir'.
"
  (let* ((runtime-dir (asdf:system-relative-pathname "chipi" *rel-runtime-dir*))
         (rel-dir (or dir runtime-dir))
         (abs-dir (merge-pathnames rel-dir runtime-dir)))
    (uiop:ensure-all-directories-exist (list abs-dir))
    abs-dir))

(defun ensure-env ()
  (ensure-runtime-dir)
  (isys:ensure-isys)
  (timer:ensure-timer)
  (cr:ensure-cron)
  t)

(defun shutdown-env ()
  (isys:shutdown-isys)
  (timer:shutdown-timer)
  (cr:shutdown-cron)
  t)
