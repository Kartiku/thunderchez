

(library (posix)
  (export strerror errno EAGAIN EINTR
	  mktemp mkstemp with-mktemp close
	  wtermsig wifexited wifsignaled wexitstatus
	  wait-for-pid file-write file-read bytes-ready)
  (import (chezscheme)
	  (only (thunder-utils) bytevector-copy*))
;;; POSIX STUFF
  (define init (load-shared-object "libc.so.6"))

  (define strerror
    (case-lambda
     [() (strerror (errno))]
     [(n)
      (define strerror* (foreign-procedure "strerror_r" (int u8* size_t) string))
      (define buff (make-bytevector 1024))
      (strerror* n buff 1024)]))

  (define (errno)
    (foreign-ref 'int (foreign-entry "errno") 0))

  (define EAGAIN 11)
  (define EINTR 4)

  (define (mkstemp template)
    (define mkstemp* (foreign-procedure "mkstemp" (u8*) int))
    (define t (string->utf8 template))
    
    (let ([fd (mkstemp* t)])
      (when (< fd 0)
	    (errorf 'mkstemp "failed: ~a" (strerror)))
      (values fd (utf8->string t))))

  (define (mktemp template)
    (define mktemp* (foreign-procedure "mktemp" (string) string))    
    (let ([s (mktemp* template)])
      (when (string=? s "")
	    (errorf 'mktemp "failed: ~a" (strerror)))
      s))

  (define (with-mktemp template f)
	  (define file (mktemp template))
	  (dynamic-wind
	      (lambda () (void))
	      (lambda () (f file))
	      (lambda () (delete-file file))))

  (define (close fd)
    (define close* (foreign-procedure "close" (int) int))
    (if (< (close* fd) 0)
	(errorf 'close "failed: ~a" (strerror))))


  (define (wtermsig x)
    (logand x #x7f))
  (define (wifexited x)
    (zero? (wtermsig x)))
  (define (wifsignaled x)
    (> (logand #xff (bitwise-arithmetic-shift-right
		     (+ 1 (wtermsig x))
		     1))
       0))
  (define (wexitstatus x)
    (bitwise-arithmetic-shift-right (logand x #xff00) 8))

  (define (wait-for-pid pid)
    (define waitpid* (foreign-procedure "waitpid" (int u8* int) int))
    (define status* (make-bytevector (foreign-sizeof 'int)))
    (let loop ()
      (let ([r (waitpid* pid status* 0)])
	(when (< r 0)
	      (errorf 'wait-for-pid "waitpid failed: ~d" (strerror)))
	(let ([status (bytevector-sint-ref status* 0 (native-endianness) (foreign-sizeof 'int))])
	  (cond [(wifexited status) (wexitstatus status)]
		[(wifsignaled status) #f]
		[(loop)])))))

  ;; these shouldn't be needed.. use just open-fd-input-port,
  ;; open-fd-output-port or open-fd-input/output-port and then use the scheme
  ;; functions...
  
  (define (file-write fd data)
    (define write* (foreign-procedure "write" (int u8* size_t) ssize_t))
    (define n (bytevector-length data))
    (let loop ([data data])
      (let ([m (bytevector-length data)])
	(cond
	 [(> m 0)
	  (let ([r (write* fd data m)])
	    (cond
	     [(< r 0)
	      (if (or (= (errno) EAGAIN) (= (errno) EINTR))
		  (loop data)
		  (errorf 'write "error writing data: ~a: ~a" (errno) (strerror)))]
	     [else
	      (loop (bytevector-copy* data r))]))]
	 [else n]))))

  (define (file-read fd n)
    (define read* (foreign-procedure "read" (int u8* size_t) ssize_t))
    (define buf (make-bytevector n))
    (let loop ()
      (let ([r (read* fd buf n)])
	(cond
	 [(>= r 0) r]
	 [(or (= (errno) EAGAIN) (= (errno) EINTR)) -1]
	 [else (loop)]))))
    (define FIONREAD #x541B)

  (define (bytes-ready fd)
    (define ioctl* (foreign-procedure "ioctl" (int int void*) int))
    (define n* (foreign-alloc (foreign-sizeof 'int)))
    (ioctl* fd FIONREAD n*)
    (let ([n (foreign-ref 'int n* 0)])
      (foreign-free n*)
      n))

) ;;library posix
