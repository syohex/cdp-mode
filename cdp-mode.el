;;; cdp-mode.el --- This package provides interface with Browser via CDP  -*- lexical-binding: t; -*-

;; Copyright (C) 2020

;; Author: (require 'websocket) <dpetrov@casanova.finxploit.com>
;; Package-Version: 0.0.1
;; Keywords: comm, tools

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; TODO: Describe

;;; Code:

(require 'websocket)
(require 'json)

;; Get ideas from here
;; https://github.com/xuchunyang/edit-chrome-textarea.el/blob/master/edit-chrome-textarea.el

(defcustom cdp-mode-host "127.0.0.1"
  "Host where the Chrome DevTools Protocol is running."
  :type 'string)

(defcustom cdp-mode-port 9222
  "Port where the Chrome DevTools Protocol is running."
  :type 'integer)

(defvar-local cdp-mode-current-connection nil
  "A 'cdp-mode-connection' object associated with the current buffer")

(cl-defstruct (cdp-mode-connection
	       (:constructor cdp-mode-make-connection-1)
	       (:copier nil))
  "Represent a websocket connections.
WS is the websocket.
ID is JSON RPC ID.
CALLBACKS is a hash-table, its key is ID, its value is a
function, which takes an argument, the JSON result."
  ws (id 0) (callbacks (make-hash-table :test #'eq))
  url title)

(defun cdp-mode--json-read-from-string (string)
  "Read JSON in String."
  (let ((json-object-type 'alist)
	(json-key-type 'symbol)
	(json-array-type 'list)
	(json-false nil)
	(json-nul nil))
    (json-read-from-string string)))

(defun cdp-mode--ws-on-message (ws frame)
  "Dispatch connection callbacks according to WS and FRAME."
  (let* ((conn (process-get (websocket-conn ws) 'edit-mode-connection))
	 (callback (cdp-connection-callbacks conn))
	 (json (cdp-mode--json-read-from-string
		(websocket-frame-text frame)))
	 (id (alist-get 'id json))
	 (result (alist-get 'result json)))
    (pcase (gethash id callbacks)
      ('nil (message "[cdp-mode] Ignored response, id=%id" id))
      (func
       (remhash id callbacks)
       (funcall func result)))))

(defun cdp-mode-make-connection (ws-url url title)
  "Connect to websocket at WS-URL, store URL and TITLE, return connection."
  (let ((ws (websocket-open ws-url :on-message #'cdp-mode--ws-on-message))
	(conn (cdp-mode-make-connection-1)))
    (setf (cdp-mode-connection-ws conn) ws)
    (setf (process-get (websocket-conn ws) 'cdp-mode-connection) conn)
    (setf (cdp-mode-connection-url conn) url)
    (setf (cdp-mode-connection-title conn) title)
    conn))

;;(setq ws
;;      (websocket-open "ws://127.0.1:9222/devtools/browser/1ab39c33-f51d-4acd-af14-74850c2433f5"
;;		      :on-message (lambda (
;;					   _websocket
;;					   frame)
;;				    (message "ws frame :%S" (websocket-frame-text frame)))
;;		      :on-close (lambda (_websocket) (message "websocket closed"))))
;;
;;(websocket-send-text ws "hello from emacs")
;;(websocket-close ws)

(defun cdp-mode-new-buffer-name (title url)
  "Return a new buffer name for TITLE and URL."
  (pcase title
    ("" url)
    (_ title)))

(defcustom cdp-mode-guess-mode-function
    #'cdp-mode-default-guess-mode-function
  "The function used to guess the major mode of an editing buffer.
It's called with the editing buffer as the current buffer.
It's called with three arguments, URL TITLE, and CONTENT."
  :type 'function)

(defun cdp-mode-default-guess-mode-function (_url _title _content)
  "Set major mode for editing buffer depending on URL, TITLE, CONTENT."
  ;; no-op
  (text-mode))

(defun cdp-mode--url-request (url)
  "Request URL, decode response body as JSON and return it."
  (with-current-buffer (url-retrieve-synchronously url)
    (goto-char url-http-end-of-headers)
    (cl-assert (= 200 url-http-response-status))
    (prog1 (cdp-mode--json-read-from-string
	    (decode-coding-string
	     (buffer-substring-no-properties (point) (point-max))
	     'utf-8))
      (kill-buffer))))

(defun cdp-mode ()
  (interactive)
  (let (title url ws-url conn)
    ;; Make connection
    ;;
    (let-alist (cdp-mode--first-page)
      (setq title .title
	    url .url
	    ws-url .webSocketDebuggerUrl))
    (message "Editing %s - %s" title url)
    (setq conn (cdp-mode-make-connection ws-url url title))
    (accept-process-output nil 0.1)

    (with-current-buffer (generate-new-buffer
			  (cdp-mode-new-buffer-name title url))
      (funcall cdp-mode-guess-mode-function url title "content")
      (setq cdp-current-connection conn)
      (select-window (display-buffer (current-buffer))))))

(defun cdp-mode--first-page ()
  "Return first page of Chrome, that is, the active tab's page"
  (car (cdp-mode--url-request
	(format "http://%s:%d/json"
		cdp-mode-host
		cdp-mode-port))))


(provide 'cdp-mode)

;;; cdp-mode.el ends here
