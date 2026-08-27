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
      (should-error (org-gcal-view-next-focus) :type 'user-error))))

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

(provide 'org-gcal-view-test)
;;; org-gcal-view-test.el ends here
