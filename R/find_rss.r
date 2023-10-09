#' Find RSS feed on a newspapers website
#'
#' @param x main domain of the newspaper site to check for RSS feeds.
#' @param use which steps to include in the search (see Details). Default is to
#'   include all.
#'
#' @details Uses a three step heuristic to find RSS feeds:
#'
#' 1. Scrapes the main page (without any paths) to see if the RSS feed is
#' advertised
#' 2. Checks a number of common paths where sites put their RSS feeds
#' 3. Queries the [feedly.com](https://feedly.com/) API to for feeds associated
#' with a page
#'
#' @references Approach inspired by <https://github.com/mediacloud/feed_seeker>
#' @return A URL to the RSS feed(s) or NULL if nothing is found
#' @export
#'
#' @examples
#' pb_find_rss("https://www.buzzfeed.com/")
#' @md
pb_find_rss <- function(x,
                        use = c("main", "suffixes", "feedly")) {

  main_rss <- NULL
  feeds <- NULL
  feedly <- list(website = NULL)

  # 1. check links on main page
  if ("main" %in% use) {
    cli::cli_progress_step("Looking through links on the main page")
    links <- rvest::read_html(url_get_basename(x)) %>%
      rvest::html_elements("a")

    descs <- links %>%
      rvest::html_text()
    urls <- links %>%
      rvest::html_attr("href")

    main_rss <- urls[grepl("\\bRSS\\b", descs) | grepl("/rss", urls)]
  }


  # 2. check common suffixes
  if ("suffixes" %in% use) {
    cli::cli_progress_step("Looking through common pahts on the site")
    common_suffixes <- c(
      "index.xml",
      "atom.xml",
      "feeds",
      "feeds/default",
      "feed",
      "feed/default",
      "feeds/posts/default/",
      "?feed=rss",
      "?feed=atom",
      "?feed=rss2",
      "?feed=rdf",
      "rss",
      "atom",
      "rdf",
      "index.rss",
      "index.rdf",
      "index.atom",
      "?type=100", # Typo3 RSS URL
      "?format=feed&type=rss", # Joomla RSS URL
      "feeds/posts/default", # Blogger.com RSS URL
      "data/rss", # LiveJournal RSS URL
      "rss.xml", # Posterous.com RSS feed
      "articles.rss",
      "articles.atom"
    )

    comb <- expand.grid(unique(adaR::ada_get_domain(x)), common_suffixes)
    urls <- paste0(comb$Var1, "/", comb$Var2)

    rss_checker <- lapply(urls, is_feed_fns)
    names(rss_checker) <- urls

    invisible(lapply(urls, function(u) {
      curl::curl_fetch_multi(
        u,
        done = rss_checker[[u]],
        fail = rss_checker[[u]]
      )
    }))
    paperboy.env$pages <- list()
    curl::multi_run(timeout = 60L)
    res <- paperboy.env$pages
    feeds <- names(res)[unlist(res)]
  }

  # 3. search feedly API
  if ("feedly" %in% use) {
    cli::cli_progress_step("Querying feedly API")
    con <- url(paste0("https://cloud.feedly.com/v3/search/feeds?query=", adaR::ada_get_domain(x)))
    lines <- readLines(con, warn = FALSE)
    feedly <- jsonlite::stream_in(textConnection(lines), verbose = FALSE)$results[[1]]
    on.exit(close(con))
  }

  out <- tibble::tibble(
    source = c(rep("landing page", length(main_rss)),
               rep("common locations", length(feeds)),
               rep("feedly API", length(feedly$website))),
    url =  c(main_rss, feeds, feedly$website)
  )
  msg <- paste0("Discovered {nrow(out)} URL{?s}",
                ifelse(nrow(out) > 1, "Check manually to see which ones fit", ""))
  cli::cli_alert_info(msg)
  return(out)
}


is_feed <- function(resp) {
  if (resp$status_code >= 400L) return(FALSE)
  if (resp$type %in% c("application/rss+xml")) return(TRUE)
  grepl("<rss.+>", rawToChar(resp$content), useBytes = TRUE)
}


is_feed_fns <- function(url) {
  function(req) {
    req <<- req
    paperboy.env$pages[[url]] <- is_feed(req)
  }
}
