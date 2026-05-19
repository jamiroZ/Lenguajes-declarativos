#lang web-server/insta

(struct blog (home posts)
  #:mutable
  #:prefab)

(struct post (title body comments)
  #:mutable
  #:prefab)

; initialize-blog! : path? -> blog
; Reads a blog from a path, if not present, returns default
(define (initialize-blog! home)

  (define (log-missing-exn-handler exn)
    (blog
     (path->string home)
     (list
      (post "First Post"
            "This is my first post"
            (list "First comment!"))

      (post "Second Post"
            "This is another post"
            (list)))))

  (define the-blog
    (with-handlers ([exn? log-missing-exn-handler])
      (with-input-from-file home read)))

  (set-blog-home! the-blog (path->string home))

  the-blog)

; save-blog! : blog -> void
; Saves the contents of a blog to its home
(define (save-blog! a-blog)

  (define (write-to-blog)
    (write a-blog))

  (with-output-to-file
   (blog-home a-blog)
   write-to-blog
   #:exists 'replace))