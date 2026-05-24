#lang web-server/insta

; render-greeting: string -> response
; Consumes a name, and produces a dynamic response.

(define (render-greeting a-name)
  (response/xexpr
   `(html
      (head
       (title "Welcome"))
      (body
       (p ,(string-append "Hello " a-name))))))

(define (start request)
  (render-greeting "Jamiro"))
