q = require 'q'
events = require 'events'
reddit = require 'rereddit'

LIMIT = 100 # number of items to retrieve per request
MAX_ATTEMPTS = 5 # number of attempts to try an API call before giving up
POLL_INTERVAL = 5000 # milliseconds between API calls
BACKTRACK_POLL_INTERVAL = 2000 # milliseconds between backtrack API calls

module.exports =

class RedditStream extends events.EventEmitter
  
  constructor: (@type, @subreddit = 'all', user_agent = 'reddit-stream bot', @user = null) ->
    reddit.user_agent = user_agent
    unless @type is 'posts' or @type is 'comments'
      throw new Error 'type must be "posts" or "comments"'
  
  login: (username, password, force = no) ->
    
    deferred = q.defer()
    
    if @user? and not force
      deferred.resolve @user
    else
      request = reddit.login username, password
      
      request.end (error, response) =>
        if error?
          deferred.reject error
        else
          @user = response
          deferred.resolve @user
    
    deferred.promise
  
  start: ->
    @getItems()
  
  getItems: (newest = '', last_newest = '', after = '', attempt = 1, is_backtracking = no) =>
    
    if @type is 'posts'
      request = reddit.read "#{@subreddit}/new"
    else if @type is 'comments'
      request = reddit.read "#{@subreddit}/comments"
    
    request.limit LIMIT
    request.as @user if @user?
    request.after after if after isnt ''
    
    request.end (error, response, user, res) =>
      
      items = response?.data?.children
      
      if error? or not items?
        console.error 'error on', (new Date())
        console.error 'could not get items:', error, response if error?
        # console.warn "bad request #{attempt}/5"
        if ++attempt <= MAX_ATTEMPTS
          setTimeout (=> @getItems newest, last_newest, after, attempt, is_backtracking), POLL_INTERVAL
        else unless is_backtracking
          setTimeout @getItems, POLL_INTERVAL
      else
        
        new_items = []
        
        if items.length > 0
          
          for item in items
            if is_backtracking
              break if item.data.name <= last_newest
            else
              break if item.data.name <= newest
            new_items.push item
          
          if items[0].data.name > newest and not is_backtracking
            last_newest = newest
            newest = items[0].data.name
          
          after = items[items.length-1].data.name
        
        if new_items.length > 0
          @emit 'new', new_items
        
        should_backtrack = new_items.length is items.length
        
        if last_newest is '' or (0 <= items.length < LIMIT)
          should_backtrack = no
        
        if is_backtracking
          if should_backtrack
            setTimeout (=> @getItems newest, last_newest, after, 1, yes), BACKTRACK_POLL_INTERVAL
        else
          if should_backtrack
            setTimeout (=> @getItems newest, last_newest, after, 1, yes), 0
          setTimeout (=> @getItems newest, last_newest), POLL_INTERVAL
