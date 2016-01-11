#lang racket
(require racket/set)
(require "utilities.rkt")
(require "functions.rkt")
(require "lambda.rkt")
(require "interp.rkt")

(provide compile-S5 collection-passes)

(define compile-S5
  (class compile-S4
    (super-new)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; uniquify : env -> S0 -> S0
    ;; Nothing changes here but uniquify must either run before type-check
    ;; or be merged with type-check in order to create a map of all identifiers
    ;; and their types. Either can be done but it is trivial to just run it
    ;; before type-check. This must occur for all future based off of this
    ;; compiler.
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; type-check : env -> S4 -> S4
    ;; id.type-map : (listof (cons symbol type))
    (define id-type-map '())
    (define/override (type-check env)
      (lambda (e)
        (match e
          [(? symbol? id)
           (let ([T ((super type-check env) id)])
             (set! id-type-map (cons (cons id T) id-type-map))
             T)]
          [`(program ,ds ... ,body)
           (set! id-type-map '())
           ((super type-check env) e)]
          [else ((super type-check env) e)])))
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; reveal-functions
    
    #|(define/override (reveal-functions funs)
      (lambda (e)
	(define recur (send this reveal-functions funs))
	(match e
           [`(lambda: ,params : ,rT ,body)
	    `(lambda: ,params : ,rT ,(recur body))]
	   [else ((super reveal-functions funs) e)]
	   )))

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; convert-to-closures : env -> S4 -> S3

    (define/public (free-variables e)
      (define (recur e) (send this free-variables e))
      (match e
	 [(? symbol?) (list e)]
	 [(? integer?) '()]
	 [`(function-ref ,f) '()]
	 [`(let ([,x ,e]) ,body)
	  (set-subtract (recur body) (list x))]
	 [#t 'Boolean]
	 [#f 'Boolean]
	 [`(if ,cnd ,thn, els)
	  (set-union (recur cnd) (recur thn) (recur els))]
	[`(lambda: ([,xs : ,Ts] ...) : ,rT ,body)
	 (set-subtract (recur body) xs)]
	[`(app ,es ...)
	 (apply set-union (map recur es))]
	[`(,op ,es ...)
	 (apply set-union (map recur es))]
	))

    (define (convert-fun-body free-vars body)
      (let loop ([xs free-vars] [i 1] [new-body body])
	(cond [(null? xs) new-body]
	      [else
	       (let ([new-body `(let ([,(car xs) (vector-ref fvs ,i)])
				  ,new-body)])
		 (loop (cdr xs) (+ i 1) new-body))])))
      
    (define/public (convert-to-closures)
      (lambda (e)
        (define (recur e) ((send this convert-to-closures) e))
        (match e
	   [(? symbol?) (values e '())]
	   [(? integer?) (values e '())]
	   [`(function-ref ,f)
	    (values `(vector (function-ref ,f)) '())] ;; create closure
	   [`(let ([,x ,e]) ,body)
	    (define-values (new-e e-fs) (recur e))
	    (define-values (new-body body-fs) (recur body))
	    (values `(let ([,x ,new-e]) ,new-body)
		    (append e-fs body-fs))]
	   [#t (values #t '())]
	   [#f (values #f '())]
	   [`(if ,cnd ,thn, els)
	    (define-values (new-cnd cnd-fs) (recur cnd))
	    (define-values (new-thn thn-fs) (recur thn))
	    (define-values (new-els els-fs) (recur els))
	    (values `(if ,new-cnd ,new-thn ,new-els)
		    (append cnd-fs thn-fs els-fs))]
	   [`(lambda: ([,xs : ,Ts] ...) : ,rT ,body)
	    (define-values (new-body body-fs) (recur body))
	    (let ([fun-name (gensym 'lambda)]
		  [params (map (lambda (x T) `[,x : ,T]) xs Ts)]
		  [free-vars (set-subtract (send this free-variables new-body)
					   xs)])
	      (values
	       `(vector (function-ref ,fun-name) ,@free-vars) ;; create closure
	       (cons `(define (,fun-name ,@(cons `[fvs : _] params)) : ,rT
			,(convert-fun-body free-vars new-body))
		     body-fs)))]
	   [`(app ,e ,es ...)
	    (define-values (new-e e-fs) (recur e))
	    (define tmp (gensym 'app))
	    (define-values (new-es es-fss) (map2 recur es))
	    (values
	     `(let ([,tmp ,new-e])
		(app (vector-ref ,tmp 0) ,tmp ,@new-es))
	     (append e-fs (apply append es-fss)))]
	   [`(define (,f [,xs : ,Ts] ...) : ,rt ,body)
	    (define-values (new-body body-fs) (recur body))
	    (let ([params (map (lambda (x T) `[,x : ,T]) xs Ts)])
	      (cons
	       `(define (,f ,@(cons `[fvs : _] params)) : ,rt 
		  ,(convert-fun-body '() new-body))
	       body-fs))]
	   [`(program ,ds ... ,body)
	    (define new-ds (apply append (map recur ds)))
	    (define-values (new-body body-fs) (recur body))
	    `(program ,@(append new-ds body-fs)
		      ,new-body)]
	   ;; Keep the below case last -Jeremy
	   [`(,op ,es ...)
	    (define-values (new-es es-fss) (map2 recur es))
	    (values `(,op ,@new-es) 
		    (apply append es-fss))]
	  )))|#

    ))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Passes
(define collection-passes
  (let ([compiler (new compile-S4)]
        [interp (new interp-S4)])
    `(("programify"
       ,(lambda (ast) 
          (match ast
            [`(program ,ds ... ,body)
             `(program ,@ds ,body)]
            [else ;; for backwards compatibility with S0 thru S2
             `(program ,ast)]))
       ,(send interp interp-scheme '()))
      ("uniquify"
       ,(send compiler uniquify '())
       ,(send interp interp-scheme '()))
      ("type-check"
       ,(send compiler type-check '())
       ,(send interp interp-scheme '()))
      ("reveal-functions"
       ,(send compiler reveal-functions '())
       ,(send interp interp-scheme '()))
      ("convert-to-closures"
       ,(send compiler convert-to-closures)
       ,(send interp interp-scheme '()))
      ("flatten"
       ,(send compiler flatten #f)
       ,(send interp interp-C '()))
      ("instruction selection"
       ,(send compiler select-instructions)
       ,(send interp interp-x86 '()))
      ("liveness analysis"
       ,(send compiler uncover-live (void))
       ,(send interp interp-x86 '()))
      ("build interference"
       ,(send compiler build-interference (void) (void))
       ,(send interp interp-x86 '()))
      ("allocate registers"
       ,(send compiler allocate-registers)
       ,(send interp interp-x86 '()))
      ("insert spill code"
       ,(send compiler patch-instructions)
       ,(send interp interp-x86 '()))
      ("print x86" ,(send compiler print-x86) #f)
      )))
    
    
    