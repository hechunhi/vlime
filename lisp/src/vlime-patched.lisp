(in-package #:cl-user)

(defpackage #:vlime-patched
  (:use #:cl
        #:vlime-protocol)
  (:export #:patch-swank))

(in-package #:vlime-patched)


(defun make-buffer ()
  (make-array 0
              :element-type '(unsigned-byte 8)
              :adjustable t
              :fill-pointer 0))

(defun read-binary-line (stream &optional (buf (make-buffer)))
  (loop for byte = (read-byte stream)
        when (not (eql byte (char-code #\linefeed)))
          do (vector-push-extend byte buf)
        else
          return buf))

(defun patch-swank ()
  (defun swank/rpc:read-message (stream package)
    (let* ((bin-line (vlime-patched::read-binary-line stream))
           (line (swank/backend:utf8-to-string bin-line))
           (json (yason:parse line)))
      (let ((form
              (swank/rpc::read-form
                (swank/rpc::prin1-to-string-for-emacs
                  (json-to-form json) package)
                package)))
        (if (client-emacs-rex-p form)
          (seq-client-to-swank form)
          (remove-client-seq form)))))

  (defun swank/rpc:write-message (message package stream)
    (let* ((*package* package)
           (json (form-to-json message)))
      (if (eql (car message) :return)
        (setf json (seq-swank-to-client json))
        (setf json (list 0 json)))
      (let* ((encoded (with-output-to-string (json-out)
                        (yason:encode json json-out)))
             (full-line (concatenate
                          'string encoded (format nil "~c~c" #\return #\linefeed)))
             (bin-line (swank/backend:string-to-utf8 full-line)))
        (write-sequence bin-line stream)
        (finish-output stream)))))
