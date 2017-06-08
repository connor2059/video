#lang racket/base

(provide (all-defined-out))
(require racket/match
         "init-mlt.rkt"
         "ffmpeg.rkt")

(struct codec-obj (orig-codec-context
                   type
                   index
                   id
                   codec
                   codec-context)
  #:mutable)

(define (empty-proc mode obj packet)
  (when packet
    (av-packet-unref packet)))

(define (stream-file file
                     #:video-callback [video-callback empty-proc]
                     #:audio-callback [audio-callback empty-proc]
                     #:subtitle-callback [subtitle-callback empty-proc]
                     #:data-callback [data-callback empty-proc]
                     #:attachment-callback [attachment-callback empty-proc]
                     #:by-index-callback [by-index-callback #f])
  ;; Open file
  (define avformat (avformat-open-input file #f #f))
  (avformat-find-stream-info avformat #f)
  ;(av-dump-format avformat 0 testfile 0)
  ;; Init Streams
  (define raw-strs (avformat-context-streams avformat))
  (define stream-table (make-hash))
  (define streams
    (for/vector ([i raw-strs]
                 [i* (in-naturals)])
      (define old-codec-ctx (avstream-codec i))
      (define codec-name (avcodec-context-codec-type* old-codec-ctx))
      (define codec-id (avcodec-context-codec-id old-codec-ctx))
      (define codec (avcodec-find-decoder codec-id))
      (define codec-ctx (avcodec-copy-context codec old-codec-ctx))
      (avcodec-open2 codec-ctx codec #f)
      (define obj (codec-obj old-codec-ctx codec-name i* codec-id codec codec-ctx))
      (hash-set! stream-table codec-name obj)
      (when by-index-callback
        (by-index-callback 'init obj #f))
      obj))
  (unless by-index-callback
    (for ([(k v) (in-hash stream-table)])
      (match k
        ['video (video-callback 'init v #f)]
        ['audio (audio-callback 'init v #f)]
        ['subtitle (subtitle-callback 'init v #f)]
        ['data (data-callback 'init v #f)]
        ['attachment (attachment-callback 'init v #f)])))
  ;; Main Loop
  (let loop ()
    (define packet (av-read-frame avformat))
    (when packet
      (define index (avpacket-stream-index packet))
      (define obj (vector-ref streams index))
      (cond [by-index-callback (by-index-callback 'loop obj packet)]
            [else
             (define type (codec-obj-type obj))
             (cond [(eq? obj (hash-ref stream-table type))
                    (match type
                      ['video (video-callback 'loop obj packet)]
                      ['audio (audio-callback 'loop obj packet)]
                      ['subtitle (subtitle-callback 'loop obj packet)]
                      ['data (data-callback 'loop obj packet)]
                      ['attachment (attachment-callback 'loop obj packet)]
                      [_ (av-packet-unref packet)])]
                   [else (av-packet-unref packet)])])
      (loop)))
  ;; Close Down
  (unless by-index-callback
    (for ([(k v) (in-hash stream-table)])
      (match k
        ['video (video-callback 'close v #f)]
        ['audio (audio-callback 'close v #f)]
        ['subtitle (subtitle-callback 'close v #f)]
        ['data (data-callback 'close v #f)]
        ['attachment (attachment-callback 'close v #f)])))
  (for ([i (in-vector streams)])
    (match i
      [(struct* codec-obj
                ([orig-codec-context orig-codec-context]
                 [codec-context codec-context]
                 [index index]))
       (when by-index-callback
         (by-index-callback 'close i #f))
       (avcodec-close orig-codec-context)
       (avcodec-close codec-context)]))
  (avformat-close-input avformat))