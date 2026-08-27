;;; org-gcal-view.el --- Google Calendar-inspired view for org-agenda -*- lexical-binding: t; -*-

;; Author: Bala Ramadurai
;; URL: https://github.com/balaramadurai/org-gcal-view
;; Package-Requires: ((emacs "27.1") (org "9.0"))
;; Version: 0.1.0
;; Keywords: calendar, org, agenda

;; Commentary:
;; A Google Calendar-inspired interface for Emacs.
;; Provides day, week, and month views with Google Calendar keyboard shortcuts.
;; Data source: org-agenda-files with clocking support.
;;
;; Features:
;; - Day view with time grid, lane-packed event blocks and hairlines
;; - Week view with columns for each day
;; - Month view with event dots
;; - Google Calendar keyboard shortcuts (d, w, m, t, j/k, arrows)
;; - Focus navigation: <up>/<down> between events / month day cells,
;;   TAB previews an event in a split, RET opens it, mouse clicks work
;;   everywhere (events open; month days jump), "/" searches titles
;; - Thin current-time hairline
;; - First day of week controlled by `modern-emacs/gcal-week-start-day'
;; - Clocking support integration (total clocked time + live clock indicator)
;; - Event creation and editing

;;; Code:

(require 'org)
(require 'org-agenda)
(require 'calendar)
(require 'cl-lib)
(require 'org-clock nil t)

(defvar org-clock-marker)

;; ============================================================
;; * Configuration
;; ============================================================

(defgroup modern-emacs/gcal nil
  "Google Calendar interface for Emacs."
  :group 'org-agenda
  :prefix "modern-emacs/gcal-")

(defcustom modern-emacs/gcal-day-start-hour 6
  "Start hour for day/week view (24h format)."
  :type 'integer
  :group 'modern-emacs/gcal)

(defcustom modern-emacs/gcal-day-end-hour 22
  "End hour for day/week view (24h format)."
  :type 'integer
  :group 'modern-emacs/gcal)

(defcustom modern-emacs/gcal-slot-minutes 30
  "Minute granularity for the day grid."
  :type 'integer
  :group 'modern-emacs/gcal)

(defcustom modern-emacs/gcal-week-start-day 1
  "Day to start week (0=Sunday, 1=Monday)."
  :type 'integer
  :group 'modern-emacs/gcal)

(defcustom modern-emacs/gcal-show-clocking t
  "Show clocking time in event blocks."
  :type 'boolean
  :group 'modern-emacs/gcal)

;; ============================================================
;; * Faces - Google Calendar inspired
;; ============================================================

(defface modern-emacs/gcal-day-title
  '((t (:height 1.4 :weight bold :underline t)))
  "Large date heading at the top of the day view.")

(defface modern-emacs/gcal-week-title
  '((t (:height 1.2 :weight bold)))
  "Title for week view.")

(defface modern-emacs/gcal-month-title
  '((t (:height 1.3 :weight bold :underline t)))
  "Title for month view.")

(defface modern-emacs/gcal-hour-label
  '((((background dark)) (:foreground "#9AA2AC"))
    (t (:foreground "#6B747F")))
  "The label shown at exact hours (HH:MM).")

(defface modern-emacs/gcal-half-hour-label
  '((((background dark)) (:foreground "#5D6672"))
    (t (:foreground "#A8AFB7")))
  "The label shown at half-hours (faint).")

(defface modern-emacs/gcal-rule
  '((((background dark)) (:underline (:color "#262C35" :position 0)))
    (t (:underline (:color "#E2E6EB" :position 0))))
  "A hairline drawn with an underline at exact hours.")

(defface modern-emacs/gcal-rule-faint
  '((((background dark)) (:underline (:color "#1F242C" :position 0)))
    (t (:underline (:color "#EFF2F5" :position 0))))
  "A fainter hairline at half-hour boundaries.")

;; Block faces for events of different kinds
(defface modern-emacs/gcal-blk-work
  '((((background dark)) (:background "#1E3340" :foreground "#DCE8EF"))
    (t (:background "#DCE8EF" :foreground "#16323F")))
  "Background for a work block (blue).")

(defface modern-emacs/gcal-blk-life
  '((((background dark)) (:background "#271F2C" :foreground "#E7DCEC"))
    (t (:background "#EDE6F0" :foreground "#3A2C42")))
  "Background for a life block (purple).")

(defface modern-emacs/gcal-blk-habit
  '((((background dark)) (:background "#1C2A22" :foreground "#DDEFE2"))
    (t (:background "#E1EDE5" :foreground "#24382C")))
  "Background for a habit block (green).")

(defface modern-emacs/gcal-blk-default
  '((((background dark)) (:background "#3b82f6" :foreground "#fff"))
    (t (:background "#60a5fa" :foreground "#000")))
  "Background for an unclassified block (Google blue).")

;; Left stripe faces
(defface modern-emacs/gcal-stripe-work
  '((((background dark)) (:background "#79B0CC"))
    (t (:background "#2C5F7C")))
  "The left stripe for a work block.")

(defface modern-emacs/gcal-stripe-life
  '((((background dark)) (:background "#B197BE"))
    (t (:background "#7A5C86")))
  "The left stripe for a life block.")

(defface modern-emacs/gcal-stripe-habit
  '((((background dark)) (:background "#7FB394"))
    (t (:background "#4A7A5E")))
  "The left stripe for a habit block.")

(defface modern-emacs/gcal-stripe-default
  '((((background dark)) (:background "#1e40af"))
    (t (:background "#1d4ed8")))
  "The left stripe for an unclassified block.")

(defface modern-emacs/gcal-blk-time
  '((((background dark)) (:foreground "#9FC4D6"))
    (t (:foreground "#4A6D80")))
  "Small time text inside a block.")

(defface modern-emacs/gcal-current-time
  '((t (:background "#dc2626" :foreground "#fff" :weight bold)))
  "Face for the current time line indicator.")

(defface modern-emacs/gcal-now-line
  '((t (:underline (:color "#dc2626" :style line))))
  "Thin hairline face for the current time indicator.
Underline-only so it never covers events like a band.")

(defface modern-emacs/gcal-focus
  '((t (:inverse-video t)))
  "Face used to pulse the focused event/day line.")

(defface modern-emacs/gcal-today-highlight
  '((((background dark)) (:background "#1a1a2e"))
    (t (:background "#f0f0ff")))
  "Background highlight for today column in week view.")

(defface modern-emacs/gcal-weekday
  '((t (:weight bold)))
  "Face for weekday names.")

(defface modern-emacs/gcal-weekend
  '((((background dark)) (:foreground "#888"))
    (t (:foreground "#666")))
  "Face for weekend day names.")

(defface modern-emacs/gcal-month-day
  '((t (:height 0.9)))
  "Face for month day numbers.")

(defface modern-emacs/gcal-month-today
  '((t (:background "#3b82f6" :foreground "#fff" :weight bold)))
  "Face for today in month view.")

(defface modern-emacs/gcal-month-event-dot
  '((((background dark)) (:foreground "#3b82f6"))
    (t (:foreground "#3b82f6")))
  "Face for event dots in month view.")

(defface modern-emacs/gcal-clocking
  '((((background dark)) (:background "#2d4a22" :foreground "#90EE90" :weight bold))
    (t (:background "#e6ffe6" :foreground "#228B22" :weight bold)))
  "Face for currently clocking event.")

;; ============================================================
;; * State Variables
;; ============================================================

(defvar modern-emacs/gcal-current-date nil
  "Currently displayed date in YYYY-MM-DD format.")

(defvar modern-emacs/gcal-current-view 'day
  "Current view mode: symbol `day', `week', or `month'.")

(defvar modern-emacs/gcal-buffer-name "*Google Calendar*"
  "Name of the Google Calendar buffer.")

;; ============================================================
;; * Timestamp Parsing
;; ============================================================

;; Matches "YYYY-MM-DD", optionally followed by " DAYNAME" and/or
;; " HH:MM" and a range end "-HH:MM".  Groups:
;;   1 year, 2 month, 3 day, 4 hour, 5 minute, 6 end-hour, 7 end-minute.
(defconst modern-emacs/gcal--ts-re
  "\\([0-9]\\{4\\}\\)-\\([0-9][0-9]\\)-\\([0-9][0-9]\\)\\(?: +[[:alpha:]]+\\)?\\(?: +\\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)\\)?\\(?:-\\([0-9]\\{1,2\\}\\):\\([0-9]\\{2\\}\\)\\)?"
  "Regex matching an Org timestamp date/time portion.")

(defun modern-emacs/gcal--parse-ts-str (str)
  "Parse Org timestamp STR.
Return \(YEAR MONTH DAY START-MINS END-MINS ALL-DAY-P) or nil.
Date-only timestamps default to 09:00-10:00 so they stay visible
and are flagged ALL-DAY-P; timed timestamps without an end default
to a 60 minute duration, never shorter than 30 minutes."
  (when (and (stringp str) (string-match modern-emacs/gcal--ts-re str))
    (let* ((year (string-to-number (match-string 1 str)))
           (month (string-to-number (match-string 2 str)))
           (day (string-to-number (match-string 3 str)))
           (hour-str (match-string 4 str))
           (start (if hour-str
                      (+ (* (string-to-number hour-str) 60)
                         (string-to-number (match-string 5 str)))
                    540))
           (end-hour-str (match-string 6 str))
           (raw-end (if end-hour-str
                        (+ (* (string-to-number end-hour-str) 60)
                           (string-to-number (match-string 7 str)))
                      (+ start 60))))
      (list year month day start
            (min 1440 (max raw-end (+ start 30)))
            (and (not hour-str) t)))))

(defun modern-emacs/gcal--parse-date-str (date-str)
  "Parse DATE-STR (YYYY-MM-DD) and return a time value."
  (let ((str (if (stringp date-str) date-str (format "%s" date-str))))
    (when (string-match modern-emacs/gcal--ts-re str)
      (encode-time 0 0 12
                   (string-to-number (match-string 3 str))
                   (string-to-number (match-string 2 str))
                   (string-to-number (match-string 1 str))))))

(defun modern-emacs/gcal--date-add-days (date-str days)
  "Add DAYS to DATE-STR (YYYY-MM-DD) and return new date string."
  (let ((str (if (stringp date-str) date-str (format "%s" date-str))))
    (let ((time (modern-emacs/gcal--parse-date-str str)))
      (when time
        (format-time-string "%Y-%m-%d" (time-add time (* days 86400)))))))

(defun modern-emacs/gcal--day-of-week (date-str)
  "Return day of week for DATE-STR (0=Sunday, 6=Saturday)."
  (let ((time (modern-emacs/gcal--parse-date-str date-str)))
    (when time
      (nth 6 (decode-time time)))))

(defun modern-emacs/gcal--week-start (date-str)
  "Return the first day of the week containing DATE-STR."
  (let* ((dow (modern-emacs/gcal--day-of-week date-str))
         (delta (mod (- dow modern-emacs/gcal-week-start-day) 7)))
    (modern-emacs/gcal--date-add-days date-str (- delta))))

(defun modern-emacs/gcal--days-in-month (date-str)
  "Return number of days in the month containing DATE-STR."
  (let* ((parts (split-string date-str "-"))
         (year (string-to-number (nth 0 parts)))
         (month (string-to-number (nth 1 parts))))
    (calendar-last-day-of-month month year)))

(defun modern-emacs/gcal--truncate (str width)
  "Truncate STR to WIDTH columns, padding with spaces if shorter."
  (let ((s (if (stringp str) str (if str (format "%s" str) ""))))
    (truncate-string-to-width s width 0 ?\s)))

;; ============================================================
;; * Event Collection
;; ============================================================

(defun modern-emacs/gcal--timestamp-kind (tags)
  "Determine block kind from TAGS."
  (cond ((member "habit" tags) 'habit)
        ((member "life" tags) 'life)
        ((member "work" tags) 'work)
        (t 'default)))

(defun modern-emacs/gcal--clocked-minutes ()
  "Sum CLOCK durations in the entry at point.  Point must be on a heading."
  (save-excursion
    (org-back-to-heading t)
    (let ((end (org-entry-end-position))
          (total 0))
      (while (re-search-forward
              "^[ \t]*CLOCK:.*=>[ \t]*\\([0-9]+:[0-9]+\\)" end t)
        (setq total
              (+ total (round (org-duration-to-minutes
                               (match-string 1))))))
      total)))

(defun modern-emacs/gcal--live-clock-p (file pos)
  "Return non-nil if the running clock is on entry at POS in FILE."
  (and (markerp org-clock-marker)
       (buffer-live-p (marker-buffer org-clock-marker))
       (equal (expand-file-name file)
              (buffer-file-name (marker-buffer org-clock-marker)))
       (= pos (marker-position org-clock-marker))))

(defun modern-emacs/gcal--blocks-in-file (file date-pred)
  "Collect event blocks from FILE for dates accepted by DATE-PRED.
DATE-PRED receives a \"YYYY-MM-DD\" string.  Each block is
\(START-MINS END-MINS TITLE KIND FILE POS CLOCKED-MINUTES LIVE-P
DATE ALL-DAY-P), sorted by start time.  Sources checked per entry:
SCHEDULED, DEADLINE, then the first active timestamp in the body."
  (let ((blocks '()))
    (when (and file (file-exists-p file))
      (with-temp-buffer
        (delay-mode-hooks (org-mode))
        (insert-file-contents file)
        (org-with-point-at 1
          (org-map-entries
           (lambda ()
             (let* ((pos (point))
                    (ts-str (or (org-entry-get (point) "SCHEDULED")
                                (org-entry-get (point) "DEADLINE")
                                (org-entry-get (point) "TIMESTAMP")))
                    (parsed (modern-emacs/gcal--parse-ts-str ts-str)))
               (when parsed
                 (let* ((date-str (format "%04d-%02d-%02d"
                                          (nth 0 parsed)
                                          (nth 1 parsed)
                                          (nth 2 parsed))))
                   (when (funcall date-pred date-str)
                     (let* ((title (or (org-entry-get (point) "ITEM") "?"))
                            (kind (modern-emacs/gcal--timestamp-kind
                                   (ignore-errors (org-get-tags))))
                            (clocked (if modern-emacs/gcal-show-clocking
                                         (ignore-errors
                                           (modern-emacs/gcal--clocked-minutes))
                                       0))
                            (live (modern-emacs/gcal--live-clock-p file pos)))
                       (push (list (nth 3 parsed) (nth 4 parsed)
                                   title kind file pos clocked live
                                   date-str (nth 5 parsed))
                             blocks)))))))))))
    (sort blocks (lambda (a b) (< (car a) (car b))))))

(defun modern-emacs/gcal--collect-blocks (date-str)
  "Collect event blocks for DATE-STR (YYYY-MM-DD) from `org-agenda-files'."
  (let ((blocks '()))
    (dolist (file (org-agenda-files))
      (setq blocks
            (append blocks
                    (modern-emacs/gcal--blocks-in-file
                     file
                     (lambda (d) (string= d date-str))))))
    (sort blocks (lambda (a b) (< (car a) (car b))))))

(defun modern-emacs/gcal--collect-week-blocks (start-date)
  "Collect all blocks for the week starting at START-DATE.
Scans each agenda file once.  Returns a list of \(DATE . BLOCKS)
in day order."
  (let* ((dates (cl-loop for i from 0 below 7
                         collect
                         (modern-emacs/gcal--date-add-days start-date i)))
         (by-date (mapcar (lambda (d) (cons d '())) dates)))
    (dolist (file (org-agenda-files))
      (dolist (b (modern-emacs/gcal--blocks-in-file
                  file (lambda (d) (member d dates))))
        (when-let ((cell (assoc (nth 8 b) by-date)))
          (push b (cdr cell)))))
    (dolist (cell by-date)
      (setcdr cell (sort (cdr cell)
                         (lambda (a b) (< (car a) (car b))))))
    by-date))

(defun modern-emacs/gcal--month-event-days (year month)
  "Return a hash table of YYYY-MM-DD -> t for days with events
in YEAR/MONTH, scanning each agenda file once."
  (let ((days (make-hash-table :test 'equal))
        (prefix (format "%04d-%02d" year month))
        (last (calendar-last-day-of-month month year)))
    (dolist (file (org-agenda-files))
      (dolist (b (modern-emacs/gcal--blocks-in-file
                  file
                  (lambda (d)
                    (and (string-prefix-p prefix d)
                         (let ((n (string-to-number (substring d 8))))
                           (<= 1 n last))))))
        (puthash (nth 8 b) t days)))
    days))

;; ============================================================
;; * Debug Helper
;; ============================================================

(defun modern-emacs/gcal-debug-collect (&optional date-str)
  "Diagnostic: report collected blocks for DATE-STR (default today)."
  (interactive)
  (let ((date-str (or date-str (format-time-string "%Y-%m-%d")))
        (blocks (modern-emacs/gcal--collect-blocks
                 (or date-str (format-time-string "%Y-%m-%d")))))
    (message "=== GCal collect for %s: %d blocks ===" date-str (length blocks))
    (dolist (b blocks)
      (message "  %02d:%02d-%02d:%02d %-30s kind=%s clocked=%s%s"
               (/ (nth 0 b) 60) (% (nth 0 b) 60)
               (/ (nth 1 b) 60) (% (nth 1 b) 60)
               (nth 2 b) (nth 3 b) (nth 6 b)
               (if (nth 7 b) " [LIVE]" "")))))

;; ============================================================
;; * Lane Assignment
;; ============================================================

(defun modern-emacs/gcal--overlaps-p (a b)
  "Return non-nil if time ranges A and B overlap."
  (< (max (nth 0 a) (nth 0 b)) (min (nth 1 a) (nth 1 b))))

(defun modern-emacs/gcal--assign-lanes (blocks)
  "Assign sorted BLOCKS to non-overlapping lanes, GCal-style.
Overlapping events pile into side-by-side lanes; the lane count
grows as needed so nothing is dropped.  Returns LANES, a list of
non-empty lane lists sorted by start time."
  (let ((lanes '()))
    (dolist (b blocks)
      (let ((lane (cl-position-if
                   (lambda (l)
                     (not (cl-some (lambda (o)
                                     (modern-emacs/gcal--overlaps-p o b))
                                   l)))
                   lanes)))
        (if lane
            (setf (nth lane lanes) (append (nth lane lanes) (list b)))
          (setq lanes (append lanes (list (list b)))))))
    lanes))

;; ============================================================
;; * Clocking Display
;; ============================================================

(defun modern-emacs/gcal--format-clocked (minutes)
  "Format clocked MINUTES as H:MM string, or nil if zero."
  (when (and minutes (> minutes 0))
    (format "%d:%02d" (/ minutes 60) (% minutes 60))))

;; ============================================================
;; * All-day Section
;; ============================================================

(defun modern-emacs/gcal--allday-chip (b width)
  "Render all-day block B as a colored chip WIDTH columns wide."
  (let* ((title (or (nth 2 b) ""))
         (kind (nth 3 b))
         (file (nth 4 b))
         (pos (nth 5 b))
         (live (nth 7 b))
         (txt (concat
               (propertize
                " " 'face (modern-emacs/gcal--kind-stripe-face kind))
               (propertize
                (modern-emacs/gcal--truncate title (max 1 (1- width)))
                'face (modern-emacs/gcal--kind-block-face kind live)
                'help-echo (format "%s\nall-day%s"
                                   title
                                   (if live " [clocking]" ""))))))
    (add-text-properties 0 (length txt)
                         (list 'gcal-file file 'gcal-pos pos
                               'gcal-title title
                               'mouse-face 'highlight)
                         txt)
    txt))

(defun modern-emacs/gcal--render-allday (blocks avail)
  "Insert an all-day section for BLOCKS within AVAIL columns.
Returns the number of lines inserted (0 if no blocks)."
  (if (null blocks)
      0
    (insert (propertize " all-day\n"
                        'face 'modern-emacs/gcal-half-hour-label))
    (let ((lines 1) (x 0) out)
      (dolist (b blocks)
        (let* ((need (min avail (+ 3 (string-width (or (nth 2 b) "")))))
               (w (min need (- avail x))))
          (when (< w 6)             ; wrap: not enough room for a chip
            (push "\n" out)
            (setq lines (1+ lines) x 0
                  w (min avail (+ 3 (string-width (or (nth 2 b) ""))))))
          (push (modern-emacs/gcal--allday-chip b w) out)
          (setq x (+ x w))))
      (insert (apply #'concat (nreverse out)) "\n")
      (1+ lines))))

;; ============================================================
;; * Day View Rendering
;; ============================================================

(defun modern-emacs/gcal--render-block-cell (b mins lw &optional grid-mins)
  "Render one grid cell for block B at slot minute MINS.
LW is the lane width; GRID-MINS is the first minute shown by the
grid (blocks starting before it are clipped).  The title shows once,
on the first visible row of the block - later rows stay as a solid
colored bar.  help-echo carries the full name and details."
  (let* ((start-mins (nth 0 b))
         (end-mins (nth 1 b))
         (title (or (nth 2 b) ""))
         (kind (nth 3 b))
         (file (nth 4 b))
         (pos (nth 5 b))
         (clocked-mins (nth 6 b))
         (clocked (modern-emacs/gcal--format-clocked clocked-mins))
         (live (nth 7 b))
         ;; First *visible* row: blocks starting before the grid top
         ;; are clipped, so their first rendered row must carry text.
         (top (= mins (max start-mins (or grid-mins 0))))
         (wide (>= lw 24))
         (body
          (when top
            (concat title
                    (when wide
                      (propertize
                       (format "  %02d:%02d-%02d:%02d"
                               (/ start-mins 60) (% start-mins 60)
                               (/ end-mins 60) (% end-mins 60))
                       'face 'modern-emacs/gcal-blk-time))
                    (when clocked
                      (propertize (format " [%s]" clocked)
                                  'face 'modern-emacs/gcal-blk-time)))))
         (tip (format "%s\n%02d:%02d–%02d:%02d%s%s"
                      title
                      (/ start-mins 60) (% start-mins 60)
                      (/ end-mins 60) (% end-mins 60)
                      (if clocked
                          (format "  ⏱ %s%s" clocked
                                  (if live " (running)" ""))
                        "")
                      (pcase kind
                        ('work "\nwork") ('life "\nlife")
                        ('habit "\nhabit") (_ ""))))
         (stripe-face (modern-emacs/gcal--kind-stripe-face kind))
         (stripe (propertize " " 'face stripe-face))
         (txt (concat stripe
                      (propertize
                       (concat " "
                               (modern-emacs/gcal--truncate
                                body (- lw 2)))
                       'face (modern-emacs/gcal--kind-block-face kind live)
                       'help-echo tip))))
    (add-text-properties 0 (length txt)
                         (list 'gcal-file file 'gcal-pos pos
                               'gcal-title title
                               'mouse-face 'highlight)
                         txt)
    txt))

(defun modern-emacs/gcal--render-day (date-str blocks)
  "Render the day view for DATE-STR with BLOCKS.
Overlapping events squeeze into side-by-side lanes; the lane
count adapts so every event stays visible."
  (let* ((slot modern-emacs/gcal-slot-minutes)
         (h0 modern-emacs/gcal-day-start-hour)
         (h1 modern-emacs/gcal-day-end-hour)
         (labw 7)
         (allday (cl-remove-if-not (lambda (b) (nth 9 b)) blocks))
         (timed (cl-remove-if (lambda (b) (nth 9 b)) blocks))
         (lanes (modern-emacs/gcal--assign-lanes timed))
         (nlanes (length lanes))
         (win (get-buffer-window nil t))
         (wwidth (if win (window-width win) (frame-width)))
         (avail (max 20 (- wwidth labw 4)))
         (lw (max 12 (/ avail (max 1 nlanes))))
         (s0 (* h0 (/ 60 slot)))
         (s1 (* h1 (/ 60 slot)))
         (grid-w (+ labw (* nlanes lw) 2))
         (day-time (modern-emacs/gcal--parse-date-str date-str)))
    (erase-buffer)
    (insert (propertize
             (if day-time
                 (format-time-string "%A, %B %d, %Y" day-time)
               (format "%s" date-str))
             'face 'modern-emacs/gcal-day-title)
            "\n\n")
    ;; All-day events sit between the title and the time grid
    (let ((ad-lines (modern-emacs/gcal--render-allday allday avail)))
      (let ((slot-idx s0))
        (while (< slot-idx s1)
          (let* ((mins (* slot-idx slot))
                 (m (% mins 60))
                 (at-hour (zerop m))
                 (label (if at-hour
                            (propertize (format "%02d:%02d  " (/ mins 60) m)
                                        'face 'modern-emacs/gcal-hour-label)
                          (propertize "       "
                                      'face 'modern-emacs/gcal-half-hour-label)))
                 (cells
                  (cl-loop for lane in lanes collect
                           (let ((b (cl-find-if
                                     (lambda (x)
                                       (and (<= (nth 0 x) mins)
                                            (< mins (nth 1 x))))
                                     lane)))
                             (if b
                                 (modern-emacs/gcal--render-block-cell
                                  b mins lw (* h0 60))
                               (make-string lw ?\s)))))
                 (line-str (concat "  " label (mapconcat #'identity cells ""))))
            (when (< (string-width line-str) grid-w)
              (setq line-str
                    (concat line-str
                            (make-string (- grid-w (string-width line-str))
                                         ?\s))))
            (when at-hour
              (add-face-text-property 0 (length line-str)
                                      'modern-emacs/gcal-rule t line-str))
            (insert line-str "\n")
            (setq slot-idx (1+ slot-idx)))))
      (modern-emacs/gcal--current-time-overlay
       date-str (+ 2 ad-lines) slot h0 h1))))

(defun modern-emacs/gcal--current-time-overlay (date-str header-lines slot h0 h1)
  "Draw the current time indicator if DATE-STR is today.
HEADER-LINES is the number of lines before the grid starts.  A thin
red hairline underlines the current slot row - no background band,
so it never covers events."
  (condition-case nil
      (let* ((now (decode-time))
             (now-mins (+ (* (nth 2 now) 60) (nth 1 now)))
             (today (format-time-string "%Y-%m-%d")))
        (when (and (string= today date-str)
                   (>= now-mins (* h0 60))
                   (< now-mins (* h1 60)))
          (let* ((mins-from-start (- now-mins (* h0 60)))
                 (target-line (+ header-lines
                                 (/ mins-from-start slot)))
                 overlay)
            (save-excursion
              (goto-char (point-min))
              (forward-line target-line)
              (setq overlay (make-overlay (line-beginning-position)
                                          (line-end-position))))
            (overlay-put overlay 'face 'modern-emacs/gcal-now-line)
            (overlay-put overlay 'priority 100)
            ;; Keep a pointer to redraw/inspect later
            (setq-local modern-emacs/gcal--now-overlay overlay))))
    (error nil)))

(defvar-local modern-emacs/gcal--now-overlay nil
  "Overlay for the current time hairline in the calendar buffer.")

;; ============================================================
;; * Week View Rendering
;; ============================================================

(defun modern-emacs/gcal--render-week (start-date)
  "Render the week view starting at START-DATE."
  (let* ((slot modern-emacs/gcal-slot-minutes)
         (h0 modern-emacs/gcal-day-start-hour)
         (h1 modern-emacs/gcal-day-end-hour)
         (today (format-time-string "%Y-%m-%d"))
         (day-blocks (modern-emacs/gcal--collect-week-blocks start-date))
         (names ["Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"])
         (win (get-buffer-window nil t))
         (wwidth (if win (window-width win) (frame-width)))
         (ndays 7)
         (col-width (max 14 (/ (- wwidth 8) ndays)))
         (labw 7)
         (grid-w (+ labw (* ndays col-width)))
         (ad-per-day (mapcar (lambda (cell)
                               (cons (car cell)
                                     (cl-remove-if-not
                                      (lambda (b) (nth 9 b))
                                      (cdr cell))))
                             day-blocks))
         (max-ad (apply #'max 0
                        (mapcar #'length (mapcar #'cdr ad-per-day))))
         (timed-per-day (mapcar (lambda (cell)
                                  (cons (car cell)
                                        (cl-remove-if
                                         (lambda (b) (nth 9 b))
                                         (cdr cell))))
                                day-blocks)))
    (erase-buffer)
    (let* ((start-time (modern-emacs/gcal--parse-date-str start-date))
           (end-date (modern-emacs/gcal--date-add-days start-date 6))
           (end-time (modern-emacs/gcal--parse-date-str end-date)))
      (insert (propertize
               (format "%s – %s\n\n"
                       (if start-time
                           (format-time-string "%B %d" start-time)
                         start-date)
                       (if end-time
                           (format-time-string "%B %d, %Y" end-time)
                         end-date))
               'face 'modern-emacs/gcal-week-title)))
    (insert (make-string labw ?\s))
    (cl-loop for (date . _) in day-blocks
             for i from 0
             do (let* ((dow (mod (+ modern-emacs/gcal-week-start-day i) 7))
                       (is-today (string= date today))
                       (is-weekend (member dow '(0 6)))
                       (face (cond (is-today 'modern-emacs/gcal-month-today)
                                   (is-weekend 'modern-emacs/gcal-weekend)
                                   (t 'modern-emacs/gcal-weekday)))
                       (date-num (substring date 8)))
                   (insert (propertize
                            (modern-emacs/gcal--truncate
                             (format "%s %s" (aref names dow) date-num)
                             col-width)
                            'face face))))
    (insert "\n")
    ;; All-day lane: one row per chip index, under the day headers
    (when (> max-ad 0)
      (cl-loop for j from 0 below max-ad do
               (insert (propertize " all-day"
                                   'face 'modern-emacs/gcal-half-hour-label))
               (pcase-dolist (`(,date . ,ads) ad-per-day)
                 (let ((chip (nth j ads)))
                   (if chip
                       (insert (modern-emacs/gcal--allday-chip
                                chip (- col-width 1)) " ")
                     (insert (propertize
                              (make-string col-width ?\s)
                              'face (if (string= date today)
                                        'modern-emacs/gcal-today-highlight
                                      'default))))))
               (insert "\n")))
    (cl-loop for h from h0 below h1 do
             (cl-loop for m from 0 below 60 by slot do
                      (let* ((mins (+ (* h 60) m))
                             (at-hour (zerop m))
                             (label (if at-hour
                                        (propertize
                                         (format "%02d:%02d  " h m)
                                         'face 'modern-emacs/gcal-hour-label)
                                      (propertize "       "
                                                  'face
                                                  'modern-emacs/gcal-half-hour-label)))
                             (line-str label))
                        (pcase-dolist (`(,date . ,blocks) timed-per-day)
                          (setq line-str
                                (concat line-str
                                        (modern-emacs/gcal--week-cell
                                         blocks mins date today col-width
                                         (* h0 60)))))
                        (when (< (string-width line-str) grid-w)
                          (setq line-str
                                (concat line-str
                                        (make-string
                                         (- grid-w (string-width line-str))
                                         ?\s))))
                        (when at-hour
                          (add-face-text-property
                           0 (length line-str)
                           'modern-emacs/gcal-rule t line-str))
                        (insert line-str "\n"))))
    (modern-emacs/gcal--current-time-overlay
     today (+ 3 max-ad) slot h0 h1)))

(defun modern-emacs/gcal--kind-block-face (kind live)
  "Return block face for KIND; LIVE clocking gets the clocking face."
  (if live
      'modern-emacs/gcal-clocking
    (pcase kind
      ('work 'modern-emacs/gcal-blk-work)
      ('life 'modern-emacs/gcal-blk-life)
      ('habit 'modern-emacs/gcal-blk-habit)
      (_ 'modern-emacs/gcal-blk-default))))

(defun modern-emacs/gcal--kind-stripe-face (kind)
  "Return left stripe face for KIND."
  (pcase kind
    ('work 'modern-emacs/gcal-stripe-work)
    ('life 'modern-emacs/gcal-stripe-life)
    ('habit 'modern-emacs/gcal-stripe-habit)
    (_ 'modern-emacs/gcal-stripe-default)))

(defun modern-emacs/gcal--block-tip (b)
  "Return the help-echo tooltip text for block B."
  (let ((start (nth 0 b)) (end (nth 1 b))
        (clocked (modern-emacs/gcal--format-clocked (nth 6 b)))
        (kind (nth 3 b)))
    (format "%s\n%02d:%02d-%02d:%02d%s%s"
            (or (nth 2 b) "")
            (/ start 60) (% start 60) (/ end 60) (% end 60)
            (if clocked
                (format "  [%s%s]" clocked
                        (if (nth 7 b) " running" ""))
              "")
            (pcase kind
              ('work "\nwork") ('life "\nlife")
              ('habit "\nhabit") (_ "")))))

(defun modern-emacs/gcal--week-cell (blocks mins date today col-width
                                           &optional grid-mins)
  "Return one week-view grid cell for slot MINS on DATE.
BLOCKS is that day's block list; TODAY highlights empty cells for
the current date.  COL-WIDTH is the column width; GRID-MINS the
first visible minute of the grid.  The title shows once per block,
on its first visible row."
  (let ((b (cl-find-if (lambda (x)
                         (and (<= (nth 0 x) mins) (< mins (nth 1 x))))
                       blocks)))
    (if b
        (concat (propertize
                 " " 'face
                 (modern-emacs/gcal--kind-stripe-face (nth 3 b)))
                (propertize
                 (concat " "
                         (if (= mins (max (nth 0 b) (or grid-mins 0)))
                             (modern-emacs/gcal--truncate
                              (or (nth 2 b) "") (- col-width 2))
                           (make-string (- col-width 2) ?\s)))
                 'face (modern-emacs/gcal--kind-block-face
                        (nth 3 b) (nth 7 b))
                 'help-echo (modern-emacs/gcal--block-tip b)
                 'gcal-file (nth 4 b)
                 'gcal-pos (nth 5 b)
                 'gcal-title (or (nth 2 b) "")
                 'mouse-face 'highlight))
      (propertize (make-string col-width ?\s)
                  'face (if (string= date today)
                            'modern-emacs/gcal-today-highlight
                          'default)))))

;; ============================================================
;; * Month View Rendering
;; ============================================================

(defun modern-emacs/gcal--render-month (date-str)
  "Render the month view for DATE-STR."
  (let* ((parts (split-string date-str "-"))
         (year (string-to-number (nth 0 parts)))
         (month (string-to-number (nth 1 parts)))
         (today (format-time-string "%Y-%m-%d"))
         (first-day (format "%04d-%02d-01" year month))
         (days-in-month (calendar-last-day-of-month month year))
         (start-dow (modern-emacs/gcal--day-of-week first-day))
         (event-days (modern-emacs/gcal--month-event-days year month))
         (names ["Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"])
         (day-names (cl-loop for k from 0 below 7
                             collect
                             (aref names
                                   (mod (+ modern-emacs/gcal-week-start-day k)
                                        7))))
         (offset (mod (- start-dow modern-emacs/gcal-week-start-day) 7)))
    (erase-buffer)
    (insert (propertize
             (format "%s %d\n\n"
                     (format-time-string
                      "%B"
                      (modern-emacs/gcal--parse-date-str first-day))
                     year)
             'face 'modern-emacs/gcal-month-title))
    (insert "  ")
    (dolist (name day-names)
      (insert (propertize (format "%-13s" name)
                          'face 'modern-emacs/gcal-weekday)))
    (insert "\n")
    (cl-loop for week from 0 to 5 do
             (insert "  ")
             (cl-loop for dow from 0 to 6 do
                      (let* ((day-num (+ 1 (- (+ (* week 7) dow) offset)))
                             (valid (and (>= day-num 1)
                                         (<= day-num days-in-month)))
                             (date (when valid
                                     (format "%04d-%02d-%02d"
                                             year month day-num)))
                             (is-today (and date (string= date today)))
                             (has-events (and date
                                              (gethash date event-days)))
                             (cell (if valid
                                       ;; 13 cols: number + gap + marker + pad
                                       (format "%2d%9s%s "
                                               day-num ""
                                               (if has-events "•" ""))
                                     (make-string 13 ?\s))))
                        (when is-today
                          (setq cell (copy-sequence cell))
                          (add-face-text-property
                           0 (length cell) 'modern-emacs/gcal-month-today
                           t cell))
                        (when has-events
                          ;; Recolor just the dot on non-today cells
                          (setq cell (copy-sequence cell))
                          (put-text-property
                           11 12
                           'face 'modern-emacs/gcal-month-event-dot cell))
                        (when valid
                          (setq cell (copy-sequence cell))
                          (put-text-property
                           0 (length cell)
                           'gcal-jump-date date cell)
                          (put-text-property
                           0 (length cell)
                           'help-echo (format "Jump to %s" date) cell)
                          (put-text-property
                           0 (length cell)
                           'mouse-face 'highlight cell))
                        (insert cell)))
             (insert "\n"))))

;; ============================================================
;; * Main Entry Points
;; ============================================================

(defun modern-emacs/gcal-day-view (&optional date)
  "Display a Google Calendar-inspired day view for DATE (or today).
When called interactively, shows today.  When called from Lisp, DATE
should be a \"YYYY-MM-DD\" string."
  (interactive)
  (let* ((date-str (or date (format-time-string "%Y-%m-%d")))
         (blocks (modern-emacs/gcal--collect-blocks date-str))
         (buf (get-buffer-create modern-emacs/gcal-buffer-name)))
    (switch-to-buffer buf)
    (setq-local line-spacing 0)
    (setq-local truncate-lines t)
    (setq modern-emacs/gcal-current-date date-str)
    (setq modern-emacs/gcal-current-view 'day)
    (let ((inhibit-read-only t))
      (modern-emacs/gcal-mode)
      (modern-emacs/gcal--render-day date-str blocks))
    (goto-char (point-min))
    (message "Google Calendar: %d events for %s" (length blocks) date-str)))

(defun modern-emacs/gcal-week-view (&optional date)
  "Display a Google Calendar-inspired week view for DATE (or today)."
  (interactive)
  (let* ((date-str (or date (format-time-string "%Y-%m-%d")))
         (week-start (modern-emacs/gcal--week-start date-str))
         (buf (get-buffer-create modern-emacs/gcal-buffer-name)))
    (switch-to-buffer buf)
    (setq-local line-spacing 0)
    (setq-local truncate-lines t)
    (setq modern-emacs/gcal-current-date date-str)
    (setq modern-emacs/gcal-current-view 'week)
    (let ((inhibit-read-only t))
      (modern-emacs/gcal-mode)
      (modern-emacs/gcal--render-week week-start))
    (goto-char (point-min))
    (message "Google Calendar: Week view starting %s" week-start)))

(defun modern-emacs/gcal-month-view (&optional date)
  "Display a Google Calendar-inspired month view for DATE (or today)."
  (interactive)
  (let* ((date-str (or date (format-time-string "%Y-%m-%d")))
         (buf (get-buffer-create modern-emacs/gcal-buffer-name)))
    (switch-to-buffer buf)
    (setq-local line-spacing 0)
    (setq-local truncate-lines t)
    (setq modern-emacs/gcal-current-date date-str)
    (setq modern-emacs/gcal-current-view 'month)
    (let ((inhibit-read-only t))
      (modern-emacs/gcal-mode)
      (modern-emacs/gcal--render-month date-str))
    (goto-char (point-min))
    (message "Google Calendar: Month view for %s" date-str)))

;; ============================================================
;; * Navigation Commands
;; ============================================================

(defun modern-emacs/gcal-today ()
  "Go to today's date."
  (interactive)
  (modern-emacs/gcal-switch-to-date (format-time-string "%Y-%m-%d")))

(defun modern-emacs/gcal-switch-to-date (date-str)
  "Redisplay the current view at DATE-STR."
  (pcase modern-emacs/gcal-current-view
    ('day (modern-emacs/gcal-day-view date-str))
    ('week (modern-emacs/gcal-week-view date-str))
    ('month (modern-emacs/gcal-month-view date-str))))

(defun modern-emacs/gcal-next ()
  "Go to next day/week/month depending on current view."
  (interactive)
  (let ((date-str modern-emacs/gcal-current-date))
    (pcase modern-emacs/gcal-current-view
      ('day (modern-emacs/gcal-day-view
             (modern-emacs/gcal--date-add-days date-str 1)))
      ('week (modern-emacs/gcal-week-view
              (modern-emacs/gcal--date-add-days date-str 7)))
      ('month (let* ((parts (split-string date-str "-"))
                     (year (string-to-number (nth 0 parts)))
                     (month (string-to-number (nth 1 parts)))
                     (next-month (if (= month 12) 1 (1+ month)))
                     (next-year (if (= month 12) (1+ year) year)))
                (modern-emacs/gcal-month-view
                 (format "%04d-%02d-01" next-year next-month)))))))

(defun modern-emacs/gcal-previous ()
  "Go to previous day/week/month depending on current view."
  (interactive)
  (let ((date-str modern-emacs/gcal-current-date))
    (pcase modern-emacs/gcal-current-view
      ('day (modern-emacs/gcal-day-view
             (modern-emacs/gcal--date-add-days date-str -1)))
      ('week (modern-emacs/gcal-week-view
              (modern-emacs/gcal--date-add-days date-str -7)))
      ('month (let* ((parts (split-string date-str "-"))
                     (year (string-to-number (nth 0 parts)))
                     (month (string-to-number (nth 1 parts)))
                     (prev-month (if (= month 1) 12 (1- month)))
                     (prev-year (if (= month 1) (1- year) year)))
                (modern-emacs/gcal-month-view
                 (format "%04d-%02d-01" prev-year prev-month)))))))

(defun modern-emacs/gcal-switch-to-day ()
  "Switch to day view."
  (interactive)
  (setq modern-emacs/gcal-current-view 'day)
  (modern-emacs/gcal-day-view modern-emacs/gcal-current-date))

(defun modern-emacs/gcal-switch-to-week ()
  "Switch to week view."
  (interactive)
  (setq modern-emacs/gcal-current-view 'week)
  (modern-emacs/gcal-week-view modern-emacs/gcal-current-date))

(defun modern-emacs/gcal-switch-to-month ()
  "Switch to month view."
  (interactive)
  (setq modern-emacs/gcal-current-view 'month)
  (modern-emacs/gcal-month-view modern-emacs/gcal-current-date))

(defun modern-emacs/gcal-refresh ()
  "Refresh the current view."
  (interactive)
  (modern-emacs/gcal-switch-to-date modern-emacs/gcal-current-date))

;; ============================================================
;; * Focus: Point, Arrows and Mouse
;; ============================================================

(defun modern-emacs/gcal--event-targets ()
  "Return distinct events in the buffer, top to bottom.
Each target is \(BUFFER-POS FILE ENTRY-POS TITLE).  Scans
`gcal-pos' rather than `gcal-file': adjacent blocks often come
from the same file, and a property walk needs changing values."
  (save-excursion
    (goto-char (point-min))
    (let ((seen (make-hash-table :test 'equal))
          (targets '()))
      (while (< (point) (point-max))
        (let ((next (next-single-property-change (point) 'gcal-pos)))
          (if (not next)
              (goto-char (point-max))
            (goto-char next)
            (let* ((p (get-text-property next 'gcal-pos))
                   (f (get-text-property next 'gcal-file)))
              (when (and f p (not (gethash (cons f p) seen)))
                (puthash (cons f p) t seen)
                (push (list (point) f p
                            (get-text-property next 'gcal-title))
                      targets))))))
      (nreverse targets))))

(defun modern-emacs/gcal--date-cell-targets ()
  "Return month-view day cells carrying `gcal-jump-date', in order.
Each target is \(BUFFER-POS nil nil DATE)."
  (save-excursion
    (goto-char (point-min))
    (let ((targets '()))
      (while (< (point) (point-max))
        (let ((next (next-single-property-change (point) 'gcal-jump-date)))
          (if (not next)
              (goto-char (point-max))
            (goto-char next)
            (let ((date (get-text-property next 'gcal-jump-date)))
              ;; Boundaries into plain whitespace/newlines carry nil.
              (when date
                (push (list (point) nil nil date) targets))))))
      (nreverse targets))))

(defun modern-emacs/gcal--focus-targets ()
  "Return focusable targets for the current view."
  (if (eq modern-emacs/gcal-current-view 'month)
      (modern-emacs/gcal--date-cell-targets)
    (modern-emacs/gcal--event-targets)))

(defun modern-emacs/gcal--current-target-key ()
  "Key identifying what is under point, or nil."
  (if (eq modern-emacs/gcal-current-view 'month)
      (get-text-property (point) 'gcal-jump-date)
    (let ((file (get-text-property (point) 'gcal-file))
          (pos (get-text-property (point) 'gcal-pos)))
      (when (and file pos) (cons file pos)))))

(defun modern-emacs/gcal--target-key (target)
  (if (eq modern-emacs/gcal-current-view 'month)
      (nth 3 target)
    (cons (nth 1 target) (nth 2 target))))

(defun modern-emacs/gcal--focus-at (pos label)
  "Move point to POS, make the cursor visible and pulse the line.
LABEL, when non-nil, is shown in the echo area."
  (goto-char pos)
  ;; The mode hides the cursor; reveal it once the user navigates.
  (setq-local cursor-type 'bar)
  (when (get-buffer-window nil t)
    (recenter-top-bottom 0))
  (when (fboundp 'pulse-momentary-highlight-one-line)
    (pulse-momentary-highlight-one-line (point)))
  (when label (message "%s" label)))

(defun modern-emacs/gcal-next-focus (&optional backward)
  "Move focus to the next event (or day cell in month view).
With BACKWARD move to the previous one.  Bound to <down>/<up>."
  (interactive)
  (let* ((targets (modern-emacs/gcal--focus-targets))
         (_ (unless targets
              (user-error "Nothing to navigate here")))
         (cur-key (modern-emacs/gcal--current-target-key))
         (next (cl-find-if
                (lambda (tgt)
                  (and (or (> (car tgt) (point))
                           ;; Same segment start counts as "on it";
                           ;; skip past all segments of current key.
                           (= (car tgt) (point)))
                       (not (equal (modern-emacs/gcal--target-key tgt)
                                   cur-key))))
                (if backward (reverse targets) targets))))
    (cond
     (next
      (modern-emacs/gcal--focus-at
       (car next)
       (or (nth 3 next) "")))
     (backward
      (user-error "At first %s"
                  (if (eq modern-emacs/gcal-current-view 'month)
                      "day" "event")))
     (t
      (user-error "At last %s"
                  (if (eq modern-emacs/gcal-current-view 'month)
                      "day" "event"))))))

(defun modern-emacs/gcal-previous-focus ()
  "Move focus to the previous event/day cell.  Bound to <up>."
  (interactive)
  (modern-emacs/gcal-next-focus 'backward))

(defun modern-emacs/gcal-open-at-point ()
  "Open the thing under point.
On an event: visit its org entry in another window (switching to
it).  On a month day cell: jump to that day's view."
  (interactive)
  (let ((file (get-text-property (point) 'gcal-file))
        (pos (get-text-property (point) 'gcal-pos))
        (date (get-text-property (point) 'gcal-jump-date)))
    (cond
     ((and file pos)
      (pop-to-buffer (find-file-noselect file))
      (goto-char pos)
      (org-fold-show-context))
     (date (modern-emacs/gcal-day-view date))
     (t (user-error "Nothing under point")))))

(defun modern-emacs/gcal-preview-event ()
  "Preview the event at point in a split window below, keeping
focus on the calendar.  On a month day cell, jump to that day."
  (interactive)
  (let ((file (get-text-property (point) 'gcal-file))
        (pos (get-text-property (point) 'gcal-pos))
        (date (get-text-property (point) 'gcal-jump-date))
        (cal-win (selected-window)))
    (cond
     ((and file pos)
      (setq-local cursor-type 'bar)
      (display-buffer (find-file-noselect file)
                      '((display-buffer-below-selected)
                        (window-height . 0.45)))
      (when-let ((w (get-buffer-window nil 'visible)))
        (with-selected-window w
          (goto-char pos)
          (org-fold-show-entry)
          (recenter-top-bottom 2)))
      (select-window cal-win)
      (message "%s" (or (get-text-property (point) 'gcal-title) "")))
     (date (modern-emacs/gcal-day-view date))
     (t (user-error "Nothing under point")))))

(defun modern-emacs/gcal-click (event)
  "Mouse-1 handler: place a visible cursor at EVENT and open it.
Clicking empty grid space just shows the cursor there."
  (interactive "e")
  (mouse-set-point event)
  (setq-local cursor-type 'bar)
  (condition-case nil
      (modern-emacs/gcal-open-at-point)
    (user-error nil)))

;; ============================================================
;; * Search ("/")
;; ============================================================

(defun modern-emacs/gcal--view-dates ()
  "Return the list of dates covered by the current view."
  (pcase modern-emacs/gcal-current-view
    ('day (list modern-emacs/gcal-current-date))
    ('week (cl-loop for i from 0 below 7
                    collect
                    (modern-emacs/gcal--date-add-days
                     (modern-emacs/gcal--week-start
                      modern-emacs/gcal-current-date)
                     i)))
    ('month (let* ((parts (split-string modern-emacs/gcal-current-date "-"))
                   (year (string-to-number (nth 0 parts)))
                   (month (string-to-number (nth 1 parts)))
                   (last (calendar-last-day-of-month month year)))
              (cl-loop for d from 1 to last
                       collect (format "%04d-%02d-%02d" year month d))))))

(defun modern-emacs/gcal--search-candidates (regexp dates)
  "Collect search candidates from DATES whose title matches REGEXP.
Returns alist of label -> block."
  (let ((blocks
         (apply #'append
                (mapcar #'modern-emacs/gcal--collect-blocks dates))))
    (delq nil
          (mapcar
           (lambda (b)
             (when (string-match-p regexp (or (nth 2 b) ""))
               (cons (format "%s  %02d:%02d-%02d:%02d  %s%s"
                             (nth 8 b)
                             (/ (nth 0 b) 60) (% (nth 0 b) 60)
                             (/ (nth 1 b) 60) (% (nth 1 b) 60)
                             (nth 2 b)
                             (if (nth 7 b) "  ●clocking" ""))
                     b)))
           blocks))))

(defun modern-emacs/gcal-search ()
  "Search events in the displayed period by title (regexp).
Selecting a result opens that day and focuses the event."
  (interactive)
  (let* ((dates (modern-emacs/gcal--view-dates))
         (cands (modern-emacs/gcal--search-candidates
                 (read-string (format "Search titles in %s (%s): "
                                      (car dates) (length dates))
                              "")
                 dates)))
    (pcase (length cands)
      (0 (user-error "No matching events"))
      (_ (let* ((sel (completing-read "Event: " cands nil t))
                (b (cdr (assoc sel cands))))
           (modern-emacs/gcal-day-view (nth 8 b))
           ;; Land on the event's first rendered row if present
           (let ((target (list (nth 4 b) (nth 5 b))))
             (save-excursion
               (goto-char (point-min))
               (while (and (< (point) (point-max))
                           (not (equal (list (get-text-property
                                              (point) 'gcal-file)
                                         (get-text-property
                                          (point) 'gcal-pos))
                                       target)))
                 (goto-char (or (next-single-property-change
                                 (point) 'gcal-file)
                                (point-max)))))
             (when (equal (list (get-text-property (point) 'gcal-file)
                                (get-text-property (point) 'gcal-pos))
                          target)
               (modern-emacs/gcal--focus-at
                (point) (or (nth 2 b) "")))))))))

;; ============================================================
;; * Event Actions (Clocking Support)
;; ============================================================

(defun modern-emacs/gcal--event-at-point ()
  "Return (FILE . POS) for the event under point, or signal user-error."
  (let ((file (get-text-property (point) 'gcal-file))
        (pos (get-text-property (point) 'gcal-pos)))
    (unless (and file pos)
      (user-error "No event under point"))
    (cons file pos)))

(defun modern-emacs/gcal-goto-event ()
  "Go to the org entry for the event at point, switching to it."
  (interactive)
  (modern-emacs/gcal-open-at-point))

(defun modern-emacs/gcal-edit-event ()
  "Edit the event at point."
  (interactive)
  (modern-emacs/gcal-open-at-point))

(defun modern-emacs/gcal-clock-in ()
  "Clock in to the event at point."
  (interactive)
  (let ((ev (modern-emacs/gcal--event-at-point)))
    (with-current-buffer (find-file-noselect (car ev))
      (goto-char (cdr ev))
      (org-clock-in)
      (message "Clocked in: %s"
               (org-entry-get (point) "ITEM")))))

(defun modern-emacs/gcal-clock-out ()
  "Clock out of the current clock."
  (interactive)
  (if (org-clocking-p)
      (progn
        (org-clock-out)
        (message "Clocked out"))
    (user-error "No active clock")))

(defun modern-emacs/gcal-create-event (title start end)
  "Create a new event TITLE on the currently displayed date.
START and END are \"HH:MM\" strings; the event is filed into the
first agenda file (or `org-default-notes-file') as an active
timestamp, then the view is refreshed."
  (interactive
   (list (read-string "Event title: ")
         (read-string "Start (HH:MM): " "09:00")
         (read-string "End (HH:MM): " "10:00")))
  (unless modern-emacs/gcal-current-date
    (user-error "No current date; open a calendar view first"))
  (unless (and (string-match "\\`[0-9]\\{1,2\\}:[0-9]\\{2\\}\\'" start)
               (string-match "\\`[0-9]\\{1,2\\}:[0-9]\\{2\\}\\'" end))
    (user-error "Times must be HH:MM"))
  (let* ((date-str modern-emacs/gcal-current-date)
         (abbr (format-time-string
                "%a" (modern-emacs/gcal--parse-date-str date-str)))
         (file (or (car (org-agenda-files)) org-default-notes-file)))
    (unless file
      (user-error "No org-agenda-files configured"))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (insert (format "\n* %s\n  <%s %s %s-%s>\n"
                      title date-str abbr start end))
      (save-buffer))
    (modern-emacs/gcal-refresh)
    (message "Created event: %s %s-%s in %s" title start end file)))

;; ============================================================
;; * Keymap - Google Calendar Shortcuts
;; ============================================================

(defun modern-emacs/gcal-quit ()
  "Quit the Google Calendar buffer."
  (interactive)
  (when (buffer-live-p (get-buffer modern-emacs/gcal-buffer-name))
    (kill-buffer modern-emacs/gcal-buffer-name)))

(defvar modern-emacs/gcal-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Navigation - Google Calendar style (periods)
    (define-key map (kbd "d") 'modern-emacs/gcal-switch-to-day)
    (define-key map (kbd "w") 'modern-emacs/gcal-switch-to-week)
    (define-key map (kbd "m") 'modern-emacs/gcal-switch-to-month)
    (define-key map (kbd "t") 'modern-emacs/gcal-today)
    (define-key map (kbd "j") 'modern-emacs/gcal-next)
    (define-key map (kbd "k") 'modern-emacs/gcal-previous)
    (define-key map (kbd "n") 'modern-emacs/gcal-next)
    (define-key map (kbd "p") 'modern-emacs/gcal-previous)
    (define-key map (kbd "f") 'modern-emacs/gcal-next)
    (define-key map (kbd "b") 'modern-emacs/gcal-previous)
    (define-key map [left] 'modern-emacs/gcal-previous)
    (define-key map [right] 'modern-emacs/gcal-next)
    ;; Focus - move between events / day cells
    (define-key map [down] 'modern-emacs/gcal-next-focus)
    (define-key map [up] 'modern-emacs/gcal-previous-focus)
    ;; View refresh
    (define-key map (kbd "g") 'modern-emacs/gcal-refresh)
    ;; Event actions
    (define-key map (kbd "RET") 'modern-emacs/gcal-open-at-point)
    (define-key map (kbd "TAB") 'modern-emacs/gcal-preview-event)
    (define-key map (kbd "e") 'modern-emacs/gcal-edit-event)
    (define-key map (kbd "c") 'modern-emacs/gcal-create-event)
    ;; Search
    (define-key map (kbd "/") 'modern-emacs/gcal-search)
    ;; Mouse: click anywhere; events open, month days jump
    (define-key map [mouse-1] 'modern-emacs/gcal-click)
    ;; Clocking
    (define-key map (kbd "i") 'modern-emacs/gcal-clock-in)
    (define-key map (kbd "o") 'modern-emacs/gcal-clock-out)
    ;; Quit
    (define-key map (kbd "q") 'modern-emacs/gcal-quit)
    map)
  "Keymap for `modern-emacs/gcal-mode'.")

;; ============================================================
;; * Major Mode
;; ============================================================

(define-derived-mode modern-emacs/gcal-mode special-mode "GCal"
  "Major mode for the Google Calendar interface."
  (setq-local cursor-type nil)
  (setq-local truncate-lines t)
  (setq-local buffer-read-only t)
  (setq-local line-spacing 0))

;; ============================================================
;; * Interactive Commands for Org Agenda Integration
;; ============================================================

(defun modern-emacs/gcal-open ()
  "Open Google Calendar in day view."
  (interactive)
  (modern-emacs/gcal-day-view))

(defun modern-emacs/gcal-open-week ()
  "Open Google Calendar in week view."
  (interactive)
  (modern-emacs/gcal-week-view))

(defun modern-emacs/gcal-open-month ()
  "Open Google Calendar in month view."
  (interactive)
  (modern-emacs/gcal-month-view))

;; ============================================================
;; * Keybindings in Org Agenda
;; ============================================================

(with-eval-after-load 'org-agenda
  (define-key org-agenda-mode-map (kbd "C-c C-c") 'modern-emacs/gcal-day-view)
  (define-key org-agenda-mode-map (kbd "C-c C-w") 'modern-emacs/gcal-week-view)
  (define-key org-agenda-mode-map (kbd "C-c C-m") 'modern-emacs/gcal-month-view))

;; Global keybindings
(global-set-key (kbd "C-c g d") 'modern-emacs/gcal-open)
(global-set-key (kbd "C-c g w") 'modern-emacs/gcal-open-week)
(global-set-key (kbd "C-c g m") 'modern-emacs/gcal-open-month)

;; ============================================================
;; * Provide module
;; ============================================================

(provide 'org-gcal-view)
;;; org-gcal-view.el ends here
