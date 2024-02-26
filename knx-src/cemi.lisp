(defpackage :knx-conn.cemi
  (:use :cl :knxutil :knxobj :address :dpt)
  (:nicknames :cemi)
  (:export #:cemi
           #:make-cemi
           #:make-default-cemi
           #:cemi-len
           #:cemi-l-data
           #:cemi-message-code
           #:cemi-ctrl1
           #:cemi-ctrl2
           #:cemi-source-addr
           #:cemi-destination-addr
           #:cemi-npdu
           #:cemi-tpci
           #:cemi-packet-num
           #:cemi-apci
           #:cemi-data
           #:parse-cemi
           ;; mcs
           #:+cemi-mc-l_data.req+
           #:+cemi-mc-l_data.con+
           #:+cemi-mc-l_data.ind+
           ;; tpci
           #:+tcpi-ucd+
           ;; apci
           #:apci-gv-read-p
           #:apci-gv-read-equal-p
           #:apci-gv-read
           #:apci-gv-response-p
           #:apci-gv-response-equal-p
           #:apci-gv-response
           #:apci-gv-write-p
           #:apci-gv-write-equal-p
           #:apci-gv-write
           #:make-apci-gv-write
           ))

(in-package :knx-conn.cemi)

(defconstant +cemi-mc-l_data.req+ #x11
  "L_Data.req (data service request")
(defconstant +cemi-mc-l_data.con+ #x2e
  "L_Data.con (data service confirmation")
(defconstant +cemi-mc-l_data.ind+ #x29
  "L_Data.ind (data service indication")
(defun cemi-l_data-p (message-code)
  "Return T if MESSAGE-CODE is a L_Data.*"
  (or (= message-code +cemi-mc-l_data.req+)
      (= message-code +cemi-mc-l_data.con+)
      (= message-code +cemi-mc-l_data.ind+)))

;; TCPI
(defconstant +tcpi-udt+ #x00
  "UDT (Unnumbered Package")
(defconstant +tcpi-ndt+ #x40
  "NDT (Numbered Package")
(defconstant +tcpi-ucd+ #x80
  "UCD (Unnumbered Control Data")
(defconstant +tcpi-ncd+ #xc0
  "NCD (Numbered Control Data")

;; Broadcast Type
(defconstant +broadcast-type-system+ #x00)
(defconstant +broadcast-type-normal+ #x01)

;; Priority
(defconstant +priority-system+ #x00)
(defconstant +priority-normal+ #x01)
(defconstant +priority-urgent+ #x02)
(defconstant +priority-low+ #x03)

;; ctrl2 values
(defconstant +hop-count-default+ 6)
(defconstant +frame-format-default+ 0)

;; APCI
(defstruct (apci-gv (:conc-name nil)))
;; +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
;; |                         0   0 | 0   0   0   0   0   0   0   0 |
;; +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
(defstruct (apci-gv-read (:include apci-gv))
  "Group Value Read"
  (start-mask #x00 :type octet :read-only t)
  (end-mask #x00 :type octet :read-only t))

(defun apci-gv-read-equal-p (apci-value)
  "Return T if APCI is a Group Value Read"
  (let ((apci (make-apci-gv-read)))
    (= apci-value (apci-gv-read-start-mask apci))))

;; +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
;; |                         0   0 | 0   1   n   n   n   n   n   n |
;; +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
(defstruct (apci-gv-response (:include apci-gv))
  "Group Value Response"
  (start-mask #x40 :type octet :read-only t)
  (end-mask #x7f :type octet :read-only t))

(defun apci-gv-response-equal-p (apci-value)
  "Return T if APCI is a Group Value Response"
  (let ((apci (make-apci-gv-response)))
    (and (>= apci-value (apci-gv-response-start-mask apci))
         (< apci-value (apci-gv-response-end-mask apci)))))

;; +-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
;; |                         0   0 | 1   0   n   n   n   n   n   n |
;; +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
(defstruct (apci-gv-write (:include apci-gv))
  "Group Value Write"
  (start-mask #x80 :type octet :read-only t)
  (end-mask #xbf :type octet :read-only t))

(defun apci-gv-write-equal-p (apci-value)
  "Return T if APCI is a Group Value Write"
  (let ((apci (make-apci-gv-write)))
    (and (>= apci-value (apci-gv-write-start-mask apci))
         (< apci-value (apci-gv-write-end-mask apci)))))


(defstruct (cemi (:include knx-obj)
                 (:conc-name cemi-)
                 (:constructor nil))
  "CEMI frame
cEMI frame
+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+-7-+-6-+-5-+-4-+-3-+-2-+-1-+-0-+
| Message Code                | Additional Info Length          |
| (1 octet = 08h)             | (1 octet)                       |
+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
| Additional Information                                        |
| (optional, variable length)                                   |
+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
| Service Information                                           |
| (variable length)                                             |
+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+"
  (message-code (error "Required message-code!") :type octet)
  (info-len (error "Required info-len!") :type octet)
  (additional-info nil :type (or null (vector octet))))

(defgeneric cemi-len (cemi)
  (:documentation "Return the length of the CEMI frame"))

(defmethod cemi-len ((cemi cemi))
  "Return the length of the CEMI frame"
  (+ 2 (cemi-info-len cemi)))

(defstruct (cemi-l-data (:include cemi)
                        (:conc-name cemi-)
                        (:constructor %make-cemi-l-data))
  "L_Data.ind (data service indication
3.3.4.4 L_Data.ind message (EMI1 / EMI2)"
  (ctrl1 (error "Required ctrl1!") :type (bit-vector 8))
  (ctrl2 (error "Required ctrl2!") :type (bit-vector 8))
  (source-addr (error "Required source-address!")
   :type knx-address)
  (destination-addr (error "Required destination-address!")
   :type knx-address)
  (npdu-len (error "Required npcu-len!") :type octet)
  (npdu nil :type (or nil (vector octet)))
  ;; TPCI (Transport Layer Control Information)
  ;; first two bits of npdu+1
  ;; 00.. .... UDT unnumbered package
  ;; 01.. .... NDT numbered package
  ;; 10.. .... UCD unnumbered control data
  ;; 11.. .... NCD numbered control data
  (tpci (error "Required tcpi!") :type octet)
  ;; ..xx xx.. packet number (of npdu+1)
  (packet-num (error "Required packet-num!") :type octet)
  ;; .... ..xx xx.. .... APCI code
  ;; .... ..00 0000 0000 group value request
  ;; .... ..00 01nn nnnn group value response
  ;; .... ..00 10nn nnnn group value write (not requested)
  ;; .... ..00 1100 0000 individual address write
  ;; .... ..01 0000 0000 individual address read
  ;; .... ..01 0100 0000 individual address response
  (apci (error "Required apci!") :type integer)
  (data nil :type (or null (vector octet))))

(defmethod cemi-len ((cemi cemi-l-data))
  "Return the length of the CEMI frame"
  (+ (call-next-method cemi)
     1 ; ctrl1
     1 ; ctrl2
     (* 2 (address:address-len))
     1 ; npdu-len
     (cemi-npdu-len cemi)))

(defun parse-cemi (data)
  "Parse CEMI frame from `DATA`"
  (let* ((message-code (elt data 0))
         (info-len (elt data 1))
         (service-info-start (+ 2 info-len))
         (additional-info (if (> info-len 0)
                              (subseq data 2 service-info-start)
                              nil))
         (service-info (subseq data service-info-start)))
    (cond
      ((cemi-l_data-p message-code)
       (let* ((ctrl1 (elt service-info 0))
              (ctrl2 (elt service-info 1))
              (source-addr (subseq service-info 2 4))
              (destination-addr (subseq service-info 4 6))
              (npdu-len (elt service-info 6))
              (npdu (if (> npdu-len 0)
                        (seq-to-array
                         (subseq service-info 7 (+ 7 npdu-len))
                         :type 'vector)
                        nil))
              (tpci (when npdu
                      (logand (elt npdu 1) #xc0)))
              (packet-num (when npdu
                            (ash (logand (elt npdu 1) #x3c) -2)))
              (apci (when npdu
                      (to-int
                       (logand (elt npdu 1) #x03)
                       (logand (elt npdu 2) #xc0))))
              (data (when npdu
                      (cond
                        ((= apci +apci-gv-read+)
                         nil)
                        ((= npdu-len 1)
                         ;; 6 bits, part of apci
                         (vector (logand (elt npdu 2) #x3f)))
                        (t
                         ;; then bytes are beyond the apci
                         (seq-to-array
                          (subseq npdu (+ 0 3) (+ 0 3 npdu-len))
                          :type 'vector))))))
         (%make-cemi-l-data
          :message-code message-code
          :info-len info-len
          :additional-info additional-info
          :ctrl1 (number-to-bit-vector ctrl1 8)
          :ctrl2 (number-to-bit-vector ctrl2 8)
          :source-addr (parse-individual-address source-addr)
          :destination-addr (if (= 0 (elt destination-addr 0))
                                (parse-individual-address destination-addr)
                                (parse-group-address destination-addr))
          :npdu-len npdu-len
          :npdu npdu
          :tpci tpci
          :packet-num packet-num
          :apci apci
          :data data
          ))))))

(defun %make-ctrl1-octet (&key (standard-frame t)
                            (repeat nil)
                            (broadcast-type +broadcast-type-normal+)
                            (priority +priority-low+)
                            (ack-request nil)
                            (err-confirm nil))
  (logior (if standard-frame (ash #x01 7) #x00)
          (if repeat 0 (ash #x01 5))
          (ash broadcast-type 4)
          (ash priority 2)
          (if ack-request #x02 #x00)
          (if err-confirm #x01 #x00)))

(defun %make-ctrl2-octet (address)
  (logior (if (knx-group-address-p address) #x80 #x00)
          (ash (logand +hop-count-default+ #x07) 4)
          (logand +frame-format-default+ #x0f)))

(defun make-default-cemi (&key message-code dest-address apci dpt)
  (let ((add-info nil)
        (ctrl1 (%make-ctrl1-octet))
        (ctrl2 (%make-ctrl2-octet dest-address))
        (source-addr (make-individual-address "0.0.0"))
        (tpci +tcpi-udt+)
        (packet-num 0))
    (%make-cemi-l-data
     :message-code message-code
     :info-len (length add-info)
     :additional-info add-info
     :ctrl1 (number-to-bit-vector ctrl1 8)
     :ctrl2 (number-to-bit-vector ctrl2 8)
     :source-addr source-addr
     :destination-addr dest-address
     :npdu-len (cond
                 ((apci-gv-read-p apci) 1)
                 ((or
                   (apci-gv-response-p apci)
                   (apci-gv-write-p apci))
                  ;; TODO: support for optimized dpts
                  (+ 1 (dpt-len dpt)))
                 (t (error "APCI not supported")))
     :npdu nil
     :tpci tpci
     :packet-num packet-num
     :apci apci
     :data dpt)))
