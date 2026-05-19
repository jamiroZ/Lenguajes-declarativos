#lang web-server/insta
(define (start request)
  (response/xexpr
   '(html
     (head (title "My Blog")),
     (body (h1 "Bajo construcción")))))
      (list 'html (list 'head (list 'title "Some title"))
            (list 'body (list 'p "This is a simple static page.")))

      '(html (head (title "Some title"))
            (body (p "This is a simple static page.")))

