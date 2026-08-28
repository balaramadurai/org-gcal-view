;;; org-gcal-view-test.el --- Tests for org-gcal-view -*- lexical-binding: t; -*-

;; This file is not part of GNU Emacs.

;;; Commentary:
;; ERT test suite for org-gcal-view.  Run with:
;;   make test
;; or directly:
;;   emacs -Q --batch -L . -l ert -l org-gcal-view.el \
;;         -l test/org-gcal-view-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-gcal-view)

(defmacro org-gcal-view-test-with-agenda-file (contents &rest body)
  "Write CONTENTS to a temp org file, use it as the sole agenda
file, and run BODY."
  (declare (indent 1))
  `(let* ((file (make-temp-file "org-gcal-view-test" nil ".org"))
          (org-agenda-files (list file)))
     (unwind-protect
         (progn
           (with-temp-file file (insert ,contents))
           ,@body)
       (delete-file file)
       (when (get-buffer org-gcal-view-buffer-name)
         (kill-buffer org-gcal-view-buffer-name)))))

;; ------------------------------------------------------------
;; Timestamp / date helpers
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-parse-ts-str-timed ()
  (should (equal (org-gcal-view--parse-ts-str "2026-08-27 Thu 09:00-10:30")
                 '(2026 8 27 540 630 nil))))

(ert-deftest org-gcal-view-test-parse-ts-str-timed-no-end ()
  ;; No explicit end: defaults to a 60 minute duration.
  (should (equal (org-gcal-view--parse-ts-str "2026-08-27 Thu 09:00")
                 '(2026 8 27 540 600 nil))))

(ert-deftest org-gcal-view-test-parse-ts-str-all-day ()
  (let ((parsed (org-gcal-view--parse-ts-str "2026-08-27 Thu")))
    (should (equal (butlast parsed) '(2026 8 27 540 600)))
    (should (nth 5 parsed))))

(ert-deftest org-gcal-view-test-parse-ts-str-nil ()
  (should (null (org-gcal-view--parse-ts-str nil)))
  (should (null (org-gcal-view--parse-ts-str "not a timestamp"))))

(ert-deftest org-gcal-view-test-parse-ts-str-min-duration ()
  ;; An end earlier than start+30 is clamped to a 30 minute minimum.
  (should (equal (org-gcal-view--parse-ts-str "2026-08-27 Thu 09:00-09:05")
                 '(2026 8 27 540 570 nil))))

(ert-deftest org-gcal-view-test-date-add-days ()
  (should (equal (org-gcal-view--date-add-days "2026-08-27" 1) "2026-08-28"))
  (should (equal (org-gcal-view--date-add-days "2026-08-27" -27) "2026-07-31"))
  (should (equal (org-gcal-view--date-add-days "2026-08-27" 0) "2026-08-27")))

(ert-deftest org-gcal-view-test-day-of-week ()
  ;; 2026-08-27 is a Thursday.
  (should (= (org-gcal-view--day-of-week "2026-08-27") 4)))

(ert-deftest org-gcal-view-test-week-start ()
  (let ((org-gcal-view-week-start-day 1)) ; Monday
    (should (equal (org-gcal-view--week-start "2026-08-27") "2026-08-24")))
  (let ((org-gcal-view-week-start-day 0)) ; Sunday
    (should (equal (org-gcal-view--week-start "2026-08-27") "2026-08-23"))))

(ert-deftest org-gcal-view-test-days-in-month ()
  (should (= (org-gcal-view--days-in-month "2026-02-01") 28))
  (should (= (org-gcal-view--days-in-month "2024-02-01") 29))
  (should (= (org-gcal-view--days-in-month "2026-08-01") 31)))

(ert-deftest org-gcal-view-test-truncate ()
  (should (equal (org-gcal-view--truncate "hello" 10) "hello     "))
  (should (equal (org-gcal-view--truncate "hello world" 5) "hello"))
  (should (equal (org-gcal-view--truncate nil 3) "   ")))

;; ------------------------------------------------------------
;; Classification / lane layout
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-timestamp-kind ()
  (should (eq (org-gcal-view--timestamp-kind '("work")) 'work))
  (should (eq (org-gcal-view--timestamp-kind '("life")) 'life))
  (should (eq (org-gcal-view--timestamp-kind '("habit")) 'habit))
  (should (eq (org-gcal-view--timestamp-kind '("habit" "work")) 'habit))
  (should (eq (org-gcal-view--timestamp-kind nil) 'default)))

(ert-deftest org-gcal-view-test-overlaps-p ()
  (should (org-gcal-view--overlaps-p '(540 600) '(555 615)))
  (should-not (org-gcal-view--overlaps-p '(540 600) '(600 660)))
  (should-not (org-gcal-view--overlaps-p '(540 600) '(605 660))))

(ert-deftest org-gcal-view-test-assign-lanes-no-overlap ()
  (let* ((a (list 540 600 "A")) (b (list 600 660 "B"))
         (lanes (org-gcal-view--assign-lanes (list a b))))
    (should (= (length lanes) 1))
    (should (equal (car lanes) (list a b)))))

(ert-deftest org-gcal-view-test-assign-lanes-overlap ()
  (let* ((a (list 540 600 "A")) (b (list 555 615 "B"))
         (lanes (org-gcal-view--assign-lanes (list a b))))
    (should (= (length lanes) 2))
    (should (equal (car (nth 0 lanes)) a))
    (should (equal (car (nth 1 lanes)) b))))

(ert-deftest org-gcal-view-test-format-clocked ()
  (should (equal (org-gcal-view--format-clocked 90) "1:30"))
  (should (null (org-gcal-view--format-clocked 0)))
  (should (null (org-gcal-view--format-clocked nil))))

;; ------------------------------------------------------------
;; Category colors
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-contrast-fg-dark-on-light ()
  ;; A light background gets the dark text color.
  (should (equal (org-gcal-view--contrast-fg "#ffffff") "#1a1a2e"))
  (should (equal (org-gcal-view--contrast-fg "#aed581") "#1a1a2e")))

(ert-deftest org-gcal-view-test-contrast-fg-light-on-dark ()
  ;; A dark background gets the light text color.
  (should (equal (org-gcal-view--contrast-fg "#000000") "#ffffff"))
  (should (equal (org-gcal-view--contrast-fg "#3b82f6") "#ffffff")))

(ert-deftest org-gcal-view-test-category-color-lookup ()
  (let ((org-gcal-view-category-colors '(("Work" . "#3b82f6"))))
    (should (equal (org-gcal-view--category-color "Work") "#3b82f6"))
    (should (null (org-gcal-view--category-color "Personal")))
    (should (null (org-gcal-view--category-color nil)))))

(ert-deftest org-gcal-view-test-kind-block-face-prefers-category-color ()
  (let ((org-gcal-view-category-colors '(("Family" . "#aed581"))))
    ;; A configured category overrides the tag-based kind face.
    (should (equal (org-gcal-view--kind-block-face 'work nil "Family")
                   (list :background "#aed581" :foreground "#1a1a2e")))
    ;; No configured color for this category: falls back to KIND.
    (should (eq (org-gcal-view--kind-block-face 'work nil "Unmapped")
               'org-gcal-view-blk-work))
    ;; A live clock always wins, even over a configured category color.
    (should (eq (org-gcal-view--kind-block-face 'work t "Family")
               'org-gcal-view-clocking))))

(ert-deftest org-gcal-view-test-day-view-uses-category-color ()
  (let ((org-gcal-view-category-colors '(("Entrepreneur" . "#4CAF50"))))
    (org-gcal-view-test-with-agenda-file
        ;; Starts at 09:30 (half-hour mark), so the row will have the
        ;; faint hairline face layered on top of the block face.
        "* Pitch\n  SCHEDULED: <2026-08-27 Thu 09:30-10:00>\n  :PROPERTIES:\n  :CATEGORY: Entrepreneur\n  :END:\n"
      (org-gcal-view-day-view "2026-08-27")
      (with-current-buffer org-gcal-view-buffer-name
        ;; The target position lands on the block's leading stripe
        ;; character (background-only face); the block body's own
        ;; face, one character further in, carries the category color
        ;; plus the faint rule face layered via add-face-text-property.
        (goto-char (1+ (caar (org-gcal-view--event-targets))))
        (let ((face (get-text-property (point) 'face)))
          ;; Face is a list: (category-color-plist rule-face-symbol)
          (should (listp face))
          (should (equal (car face)
                         (list :background "#4CAF50" :foreground "#1a1a2e")))
          (should (eq (cadr face) 'org-gcal-view-rule-faint)))))))

;; ------------------------------------------------------------
;; Work / Personal filter ("P")
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-category-passes-filter-p ()
  (let ((org-gcal-view-work-categories '("Work" "Entrepreneur")))
    (let ((org-gcal-view-work-filter-state nil))
      (should (org-gcal-view--category-passes-filter-p "Work"))
      (should (org-gcal-view--category-passes-filter-p "Family")))
    (let ((org-gcal-view-work-filter-state 'work))
      (should (org-gcal-view--category-passes-filter-p "Work"))
      (should-not (org-gcal-view--category-passes-filter-p "Family")))
    (let ((org-gcal-view-work-filter-state 'personal))
      (should-not (org-gcal-view--category-passes-filter-p "Work"))
      (should (org-gcal-view--category-passes-filter-p "Family")))))

(ert-deftest org-gcal-view-test-toggle-work-personal-cycles-and-filters ()
  (let ((org-gcal-view-work-categories '("Work"))
        (org-gcal-view-work-filter-state nil))
    (org-gcal-view-test-with-agenda-file
        "* Standup\n  SCHEDULED: <2026-08-27 Thu 09:00-10:00>\n  :PROPERTIES:\n  :CATEGORY: Work\n  :END:\n* Birthday\n  SCHEDULED: <2026-08-27 Thu 11:00-12:00>\n  :PROPERTIES:\n  :CATEGORY: Family\n  :END:\n"
      (org-gcal-view-day-view "2026-08-27")
      (with-current-buffer org-gcal-view-buffer-name
        (should (= (length (org-gcal-view--event-targets)) 2))
        (org-gcal-view-toggle-work-personal)
        (should (eq org-gcal-view-work-filter-state 'work))
        (should (= (length (org-gcal-view--event-targets)) 1))
        (should (org-gcal-view-test--line-at "Standup"))
        (should-not (org-gcal-view-test--line-at "Birthday"))
        (org-gcal-view-toggle-work-personal)
        (should (eq org-gcal-view-work-filter-state 'personal))
        (should-not (org-gcal-view-test--line-at "Standup"))
        (should (org-gcal-view-test--line-at "Birthday"))
        (org-gcal-view-toggle-work-personal)
        (should (null org-gcal-view-work-filter-state))
        (should (= (length (org-gcal-view--event-targets)) 2))))))

(ert-deftest org-gcal-view-test-toggle-work-personal-requires-categories ()
  (let ((org-gcal-view-work-categories nil))
    (should-error (org-gcal-view-toggle-work-personal) :type 'user-error)))

;; ------------------------------------------------------------
;; Org-buffer-backed event collection
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-collect-blocks ()
  (org-gcal-view-test-with-agenda-file
      "* Event A :work:\n  <2026-08-27 Thu 09:00-10:00>\n* Event B :life:\n  <2026-08-27 Thu 11:00-12:00>\n* Other day\n  <2026-08-28 Fri 09:00-10:00>\n"
    (let ((blocks (org-gcal-view--collect-blocks "2026-08-27")))
      (should (= (length blocks) 2))
      (should (equal (nth 2 (nth 0 blocks)) "Event A"))
      (should (eq (nth 3 (nth 0 blocks)) 'work))
      (should (equal (nth 2 (nth 1 blocks)) "Event B")))))

;; ------------------------------------------------------------
;; Rendering
;; ------------------------------------------------------------

(defun org-gcal-view-test--line-at (title)
  "Return the buffer line containing TITLE, or nil."
  (save-excursion
    (goto-char (point-min))
    (let (found)
      (while (and (not found) (not (eobp)))
        (let ((line (buffer-substring (line-beginning-position)
                                      (line-end-position))))
          (when (string-match-p (regexp-quote title) line)
            (setq found line)))
        (forward-line 1))
      found)))

(ert-deftest org-gcal-view-test-day-view-title-visible-off-slot-start ()
  ;; An event starting at a minute that isn't on a slot boundary (here
  ;; :07, vs. the default 30-minute grid) must still show its title
  ;; once, not render as a blank colored bar for its whole duration -
  ;; the row's exact minute never equals such a start time.
  (org-gcal-view-test-with-agenda-file
      "* Odd Start\n  <2026-08-27 Thu 20:07-21:00>\n"
    (org-gcal-view-day-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (should (org-gcal-view-test--line-at "Odd Start")))))

(ert-deftest org-gcal-view-test-week-view-title-visible-off-slot-start ()
  (org-gcal-view-test-with-agenda-file
      "* Odd Start\n  <2026-08-24 Mon 20:07-21:00>\n"
    (org-gcal-view-week-view "2026-08-24")
    (with-current-buffer org-gcal-view-buffer-name
      (should (org-gcal-view-test--line-at "Odd Start")))))

(ert-deftest org-gcal-view-test-day-view-title-shown-once-per-block ()
  ;; Regardless of slot alignment, the title must appear on exactly
  ;; one row of a multi-row block, not every row (which would defeat
  ;; the "solid bar below the title" look) and not zero rows.
  (org-gcal-view-test-with-agenda-file
      "* Long Event\n  <2026-08-27 Thu 09:00-11:00>\n"
    (org-gcal-view-day-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (point-min))
      (let ((count 0))
        (while (not (eobp))
          (when (string-match-p
                 "Long Event"
                 (buffer-substring (line-beginning-position)
                                   (line-end-position)))
            (setq count (1+ count)))
          (forward-line 1))
        (should (= count 1))))))

;; ------------------------------------------------------------
;; Day-view same-row navigation (overlapping events)
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-row-hop-between-overlapping-events ()
  (org-gcal-view-test-with-agenda-file
      "* Event A\n  <2026-08-27 Thu 09:00-10:00>\n* Event B\n  <2026-08-27 Thu 09:15-10:15>\n"
    (org-gcal-view-day-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (point-min))
      (let (found)
        (while (and (not found) (< (point) (point-max)))
          (when (> (length (org-gcal-view--row-targets)) 1) (setq found t))
          (unless found (forward-line 1)))
        (should found)
        (goto-char (caar (org-gcal-view--row-targets))))
      (should (equal (get-text-property (point) 'gcal-title) "Event A"))
      (org-gcal-view-right)
      (should (equal (get-text-property (point) 'gcal-title) "Event B"))
      (should-error (org-gcal-view-right) :type 'user-error)
      (org-gcal-view-left)
      (should (equal (get-text-property (point) 'gcal-title) "Event A"))
      (should-error (org-gcal-view-left) :type 'user-error))))

(ert-deftest org-gcal-view-test-collect-blocks-scheduled-shadows-body-timestamp ()
  ;; The fast-path scan in `org-gcal-view--blocks-in-file' finds
  ;; candidates by searching for the raw date string anywhere in the
  ;; file, which would also match a body timestamp under an entry
  ;; SCHEDULED for a different date.  SCHEDULED must still win.
  (org-gcal-view-test-with-agenda-file
      "* Shadowed Entry\n  SCHEDULED: <2026-08-01 Sat>\n  See also <2026-08-27 Thu 10:00> for context.\n* Real Entry\n  <2026-08-27 Thu 09:00-10:00>\n"
    (let ((blocks (org-gcal-view--collect-blocks "2026-08-27")))
      (should (= (length blocks) 1))
      (should (equal (nth 2 (car blocks)) "Real Entry")))))

(ert-deftest org-gcal-view-test-right-falls-back-to-next-day-when-single-event ()
  (org-gcal-view-test-with-agenda-file
      "* Solo Event\n  <2026-08-27 Thu 09:00-10:00>\n"
    (org-gcal-view-day-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (caar (org-gcal-view--event-targets)))
      (org-gcal-view-right)
      (should (equal org-gcal-view-current-date "2026-08-28")))))

;; ------------------------------------------------------------
;; Week-view day-to-day and same-day navigation
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-week-view-day-hop ()
  (org-gcal-view-test-with-agenda-file
      "* Mon Event\n  <2026-08-24 Mon 09:00-10:00>\n* Tue Event\n  <2026-08-25 Tue 09:00-10:00>\n"
    (org-gcal-view-week-view "2026-08-24")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (caar (org-gcal-view--event-targets)))
      (should (equal (get-text-property (point) 'gcal-title) "Mon Event"))
      (org-gcal-view-right)
      (should (equal (get-text-property (point) 'gcal-title) "Tue Event"))
      (org-gcal-view-left)
      (should (equal (get-text-property (point) 'gcal-title) "Mon Event")))))

(ert-deftest org-gcal-view-test-week-view-same-day-up-down ()
  (org-gcal-view-test-with-agenda-file
      "* Early\n  <2026-08-24 Mon 09:00-10:00>\n* Late\n  <2026-08-24 Mon 14:00-15:00>\n* Other Day\n  <2026-08-25 Tue 09:00-10:00>\n"
    (org-gcal-view-week-view "2026-08-24")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (caar (org-gcal-view--event-targets)))
      (should (equal (get-text-property (point) 'gcal-title) "Early"))
      (org-gcal-view-next-focus)
      (should (equal (get-text-property (point) 'gcal-title) "Late"))
      ;; "Other Day" is on Tuesday, so this must not cross into it.
      (should-error (org-gcal-view-next-focus) :type 'user-error)
      ;; Backward must actually go backward, not repeat the forward hop.
      (org-gcal-view-previous-focus)
      (should (equal (get-text-property (point) 'gcal-title) "Early"))
      (should-error (org-gcal-view-previous-focus) :type 'user-error))))

(ert-deftest org-gcal-view-test-day-view-up-down-through-three-events ()
  (org-gcal-view-test-with-agenda-file
      "* First\n  <2026-08-27 Thu 07:00-08:00>\n* Second\n  <2026-08-27 Thu 09:00-10:00>\n* Third\n  <2026-08-27 Thu 11:00-12:00>\n"
    (org-gcal-view-day-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (caar (org-gcal-view--event-targets)))
      (should (equal (get-text-property (point) 'gcal-title) "First"))
      (org-gcal-view-next-focus)
      (should (equal (get-text-property (point) 'gcal-title) "Second"))
      (org-gcal-view-next-focus)
      (should (equal (get-text-property (point) 'gcal-title) "Third"))
      (should-error (org-gcal-view-next-focus) :type 'user-error)
      (org-gcal-view-previous-focus)
      (should (equal (get-text-property (point) 'gcal-title) "Second"))
      (org-gcal-view-previous-focus)
      (should (equal (get-text-property (point) 'gcal-title) "First"))
      (should-error (org-gcal-view-previous-focus) :type 'user-error))))

;; ------------------------------------------------------------
;; Jump to date
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-jump-to-date ()
  (org-gcal-view-test-with-agenda-file
      "* Event\n  <2026-09-15 Tue 09:00-10:00>\n"
    (org-gcal-view-day-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (cl-letf (((symbol-function 'org-read-date) (lambda (&rest _) "2026-09-15")))
        (org-gcal-view-jump-to-date))
      (should (equal org-gcal-view-current-date "2026-09-15")))))

;; ------------------------------------------------------------
;; Save buffers ("s")
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-save-buffers ()
  (org-gcal-view-test-with-agenda-file
      "* Event\n  <2026-08-27 Thu 09:00-10:00>\n"
    (org-gcal-view-day-view "2026-08-27")
    ;; Dirty the agenda file's buffer, then confirm "s" flushes it.
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (insert "\n* Untitled\n")
      (should (buffer-modified-p))
      (with-current-buffer org-gcal-view-buffer-name
        (org-gcal-view-save-buffers))
      (should-not (buffer-modified-p)))))

;; ------------------------------------------------------------
;; Org-agenda-style outline-path echo message
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-outline-path-message-includes-file-and-headings ()
  ;; Mirrors what `org-agenda-do-context-action' shows for the same
  ;; entry in org-agenda: "basename.org/Parent/Child", excluding the
  ;; entry's own heading (its title is already visible on the block).
  (org-gcal-view-test-with-agenda-file
      "* Parent\n** Child\n   <2026-08-27 Thu 09:00-10:00>\n"
    (let* ((blocks (org-gcal-view--collect-blocks "2026-08-27"))
           (b (car blocks))
           (msg (org-gcal-view--outline-path-message (nth 4 b) (nth 5 b))))
      (should (string-match-p (regexp-quote (file-name-nondirectory file)) msg))
      (should (string-match-p "Parent" msg))
      (should-not (string-match-p "Child" msg)))))

(ert-deftest org-gcal-view-test-focus-at-shows-outline-path-not-bare-title ()
  (org-gcal-view-test-with-agenda-file
      "* Meetings\n** Standup\n   <2026-08-27 Thu 09:00-10:00>\n"
    (org-gcal-view-day-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (let ((messages nil))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
          (org-gcal-view--focus-at (car (org-gcal-view--event-targets))))
        (should (string-match-p "Meetings" (car messages)))
        (should-not (string= (car messages) "Standup"))))))

(ert-deftest org-gcal-view-test-month-view-focus-still-shows-date ()
  ;; Month-view day-cell targets carry no FILE/ENTRY-POS, so
  ;; `org-gcal-view--focus-at' must fall back to the target's own
  ;; label (the date) instead of trying to build an outline path.
  (org-gcal-view-test-with-agenda-file
      "* Event\n  <2026-08-15 Sat 09:00-10:00>\n"
    (org-gcal-view-month-view "2026-08-01")
    (with-current-buffer org-gcal-view-buffer-name
      (let ((messages nil)
            (cell (cl-find-if (lambda (tgt) (equal (nth 3 tgt) "2026-08-15"))
                              (org-gcal-view--date-cell-targets))))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
          (org-gcal-view--focus-at cell))
        (should (equal (car messages) "2026-08-15"))))))

;; ------------------------------------------------------------
;; Cancelled and DONE events with strikethrough
;; ------------------------------------------------------------

(defun org-gcal-view-test-has-strikethrough-p (face-prop)
  "Check if FACE-PROP (single face or list of faces) contains strike-through."
  (let ((faces (if (listp face-prop) face-prop (list face-prop))))
    (cl-some (lambda (f)
               (and (listp f) (plist-get f :strike-through)))
             faces)))

(ert-deftest org-gcal-view-test-cancelled-event-has-strikethrough ()
  ;; Cancelled events (TODO state "CANCELLED") should be collected with
  ;; the correct TODO state.  Non-cancelled events should not have CANCELLED.
  (org-gcal-view-test-with-agenda-file
      "#+TODO: TODO CANCELLED | DONE\n* TODO Regular Event\n  <2026-08-27 Thu 09:00-10:00>\n* CANCELLED Cancelled Event\n  <2026-08-27 Thu 11:00-12:00>\n"
    (let* ((blocks (org-gcal-view--collect-blocks "2026-08-27"))
           (regular (cl-find-if (lambda (b) (string= (nth 2 b) "Regular Event")) blocks))
           (cancelled (cl-find-if (lambda (b) (string= (nth 2 b) "Cancelled Event")) blocks)))
      (should regular)
      (should cancelled)
      (should-not (string= (nth 11 regular) "CANCELLED"))
      (should (string= (nth 11 cancelled) "CANCELLED")))))

(ert-deftest org-gcal-view-test-cancelled-day-view-strikethrough ()
  (org-gcal-view-test-with-agenda-file
      "#+TODO: TODO CANCELLED | DONE\n* CANCELLED Cancelled Meeting\n  <2026-08-27 Thu 09:00-10:00>\n"
    (org-gcal-view-day-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (point-min))
      (let ((has-strikethrough nil))
        (while (< (point) (point-max))
          ;; Check if any position with this title has strikethrough
          (when (and (equal "Cancelled Meeting" (get-text-property (point) 'gcal-title))
                     (org-gcal-view-test-has-strikethrough-p
                      (get-text-property (point) 'face)))
            (setq has-strikethrough t))
          (forward-char))
        (should has-strikethrough)))))

(ert-deftest org-gcal-view-test-cancelled-week-view-strikethrough ()
  (org-gcal-view-test-with-agenda-file
      "#+TODO: TODO CANCELLED | DONE\n* CANCELLED Cancelled Task\n  <2026-08-27 Thu 14:00-15:00>\n"
    (org-gcal-view-week-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (point-min))
      (let ((found nil))
        (while (and (not found) (< (point) (point-max)))
          ;; Search for the title text property, not just any line containing the text
          (when (equal "Cancelled Task" (get-text-property (point) 'gcal-title))
            (setq found (text-properties-at (point))))
          (forward-char))
        (should found)
        (should (org-gcal-view-test-has-strikethrough-p (plist-get found 'face)))))))

(ert-deftest org-gcal-view-test-done-event-has-strikethrough ()
  ;; DONE events should also render with strikethrough, just like CANCELLED.
  (org-gcal-view-test-with-agenda-file
      "#+TODO: TODO | DONE\n* DONE Completed Task\n  <2026-08-27 Thu 14:00-15:00>\n"
    (org-gcal-view-day-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (point-min))
      (let ((has-strikethrough nil))
        (while (< (point) (point-max))
          (when (and (equal "Completed Task" (get-text-property (point) 'gcal-title))
                     (org-gcal-view-test-has-strikethrough-p
                      (get-text-property (point) 'face)))
            (setq has-strikethrough t))
          (forward-char))
        (should has-strikethrough)))))

;; ------------------------------------------------------------
;; Week view overlapping events with "+n" indicator
;; ------------------------------------------------------------

(ert-deftest org-gcal-view-test-week-view-overlapping-shows-plus-indicator ()
  ;; When multiple events overlap at the same time in week view, show
  ;; the first event's title with a "+n" indicator appended.
  (org-gcal-view-test-with-agenda-file
      "* Meeting A\n  <2026-08-27 Thu 10:00-11:00>\n* Meeting B\n  <2026-08-27 Thu 10:00-11:00>\n* Meeting C\n  <2026-08-27 Thu 10:30-11:00>\n"
    (org-gcal-view-week-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (point-min))
      (let ((found-plus nil))
        (while (< (point) (point-max))
          (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
            ;; Look for "+2" or "+1" in a line that also contains "Meeting A"
            (when (and (string-match "Meeting A" line)
                       (string-match "\\+[0-9]" line))
              (setq found-plus t)))
          (forward-line))
        (should found-plus)))))

(ert-deftest org-gcal-view-test-week-view-overlapping-help-echo-lists-all ()
  ;; The help-echo on an overlapping slot should list all events.
  (org-gcal-view-test-with-agenda-file
      "* Meeting A\n  <2026-08-27 Thu 10:00-11:00>\n* Meeting B\n  <2026-08-27 Thu 10:00-11:00>\n"
    (org-gcal-view-week-view "2026-08-27")
    (with-current-buffer org-gcal-view-buffer-name
      (goto-char (point-min))
      (let ((found-tooltip nil))
        (while (and (not found-tooltip) (< (point) (point-max)))
          (when (equal "Meeting A" (get-text-property (point) 'gcal-title))
            (let ((tip (get-text-property (point) 'help-echo)))
              (when (and tip
                         (string-match-p "Meeting A" tip)
                         (string-match-p "Meeting B" tip))
                (setq found-tooltip t))))
          (forward-char))
        (should found-tooltip)))))

(provide 'org-gcal-view-test)
;;; org-gcal-view-test.el ends here
