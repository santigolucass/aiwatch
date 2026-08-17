# frozen_string_literal: true

module Aiwatch
  # One line of a session's scrolling event feed: `at` may be nil (a few
  # line types carry no timestamp), `kind` is a symbol
  # (:assistant/:tool/:user/:result/:system/:compact/:pr), `text` is
  # already a short, display-ready string.
  FeedEvent = Struct.new(:at, :kind, :text)
end
