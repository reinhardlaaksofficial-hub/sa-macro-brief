# Notification hooks for the scheduled watcher.
#
# Disabled by default and inert until configured: with no configuration the
# watcher writes its PDF and says nothing. Credentials are NEVER stored in
# this repository - the Slack webhook URL is read from an environment
# variable named in config/notify.yaml, and the email path shells out to a
# mail command you control.

notify_config <- function(root = here::here()) {
  path <- file.path(root, "config", "notify.yaml")
  if (!file.exists(path)) return(list(enabled = FALSE))
  yaml::read_yaml(path)$notify %||% list(enabled = FALSE)
}

#' One-line summary of a built brief, used as the notification text.
notify_message <- function(release, period, root = here::here()) {
  payload_path <- file.path(root, "output",
                            sprintf("payload_%s_%s.rds", release, period))
  title <- sprintf("%s %s", toupper(release), period)
  if (!file.exists(payload_path)) return(sprintf("%s briefing is ready.", title))
  p <- readRDS(payload_path)
  headline <- paste(vapply(p$glance, function(g) sprintf("%s %s", g$label, g$value), ""),
                    collapse = "  |  ")
  sprintf("*%s briefing is ready*\n%s\n\n%s", p$title, headline, p$commentary[1])
}

#' Post to a Slack incoming webhook. The URL comes from the environment
#' variable named in config, so it never lands in git.
notify_slack <- function(text, cfg) {
  var <- cfg$slack_webhook_env %||% "SA_BRIEF_SLACK_WEBHOOK"
  url <- Sys.getenv(var, unset = "")
  if (!nzchar(url)) {
    message("Slack notification skipped: ", var, " is not set.")
    return(invisible(FALSE))
  }
  resp <- tryCatch(
    httr2::req_perform(
      httr2::req_body_json(
        httr2::req_timeout(httr2::request(url), 30),
        list(text = text))),
    error = function(e) e)
  if (inherits(resp, "error")) {
    message("Slack notification failed: ", conditionMessage(resp))
    return(invisible(FALSE))
  }
  invisible(TRUE)
}

#' Send email by handing the message to a mail command you configure
#' (msmtp, mailx, sendmail, or any script). No SMTP credentials are handled
#' here; the command owns authentication.
#' The template may contain {to}, {subject} and {attachment}.
notify_email <- function(text, subject, attachment, cfg) {
  cmd_template <- cfg$email$command %||% ""
  to <- cfg$email$to %||% ""
  if (!nzchar(cmd_template) || !nzchar(to)) {
    message("Email notification skipped: no command/recipient configured.")
    return(invisible(FALSE))
  }
  cmd <- gsub("{to}", shQuote(to), cmd_template, fixed = TRUE)
  cmd <- gsub("{subject}", shQuote(subject), cmd, fixed = TRUE)
  cmd <- gsub("{attachment}", shQuote(attachment), cmd, fixed = TRUE)
  status <- tryCatch(system2("/bin/sh", c("-c", shQuote(cmd)),
                             input = text, stdout = TRUE, stderr = TRUE),
                     error = function(e) conditionMessage(e))
  invisible(TRUE)
}

#' Notify all configured channels that a brief was built.
notify_brief <- function(release, period, pdf_path, root = here::here()) {
  cfg <- notify_config(root)
  if (!isTRUE(cfg$enabled)) return(invisible(FALSE))
  text <- notify_message(release, period, root)
  subject <- sprintf("%s %s briefing", toupper(release), period)
  if (isTRUE(cfg$slack$enabled)) notify_slack(text, cfg$slack)
  if (isTRUE(cfg$email$enabled)) notify_email(text, subject, pdf_path, cfg)
  invisible(TRUE)
}
