#lang web-server/insta

(struct post (title body))

; render-posts : (listof post) -> xexpr
(define (render-posts posts)
  `(div ((class "posts"))
        ,@(map render-post posts)))

; render-post : post -> xexpr
(define (render-post p)
  `(div ((class "post"))
        ,(post-title p)
        (p ,(post-body p))))

(define sample-posts
  (list
   (post "Post 1" "Body 1")
   (post "Post 2" "Body 2")))

(define (start request)
  (response/xexpr
   `(html
      (head
       (title "Blog"))
      (body
       ,(render-posts sample-posts)))))