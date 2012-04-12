# UnQL for Node.js
## SQL for NoSQL, just what the doctor ordered

So you've got your fancy new CouchDB instance running. You're ready to change the world with your local mobile social webappsitething just as soon as your $5m funding round closes.

But then your co-founder comes up to you and says "hey Dave, we've got a bit of junk data. Can you delete any checkins in the last week from a username with more than 3 numbers at the end?"

Uh oh. 

## Don't panic

```
> delete from checkins where username.match(/\d{4}$/) && timestamp > (new Date()).getTime()-1000*60*60*24*7
```

"Great work, Dave! While you're at it, can you make a new database with just the email and username of every user who hasn't logged in for a month?"

```
> create collection nag_old_users
> insert into nag_old_users select {username: username, email: email} from user where last_login < (new Date()).getTime()-1000*60*60*24*7
```

"Oh, and I accidentally checked in somewhere that might not go down well in our meeting with USV. Reckon you could take care of it?"

```
> update checkins set location = "Gretchen's Flower Shop" where username=="bob" && location=="Gretchen's Pleasure Parlor"
```

## How do I get it?

You need [node](http://www.nodejs.org) and [npm](http://npmjs.org). Once you have those:

```
npm install -g unql
```

And you can run it with `unql` on the command line.

## What can I do with it?

UnQL-node is based on the [UnQL spec](http://unqlspec.org), which means you can do most of the things listed [here](http://www.unqlspec.org/display/UnQL/Example+Queries+and+Usage) and some of the things listed [here](http://www.unqlspec.org/display/UnQL/Syntax+Summary).

Currently supported:

* SELECT [expression] FROM db [WHERE condition]
* INSERT INTO db VALUE data
* INSERT INTO db SELECT [expression] FROM db [WHERE condition]
* UPDATE db SET foo=bar,foo2=bar2
* DELETE FROM db [WHERE condition]
* CREATE/DROP COLLECTION db
* SHOW COLLECTIONS

Whenever it says "expression" or "condition", that's an arbitrary Javascript expression evaluated in the context of each row. 'db' can be the name of a database on the current couch server, or a full URL to a couch database.

Currently not supported:

* Upsert (UPDATE ... ELSE INSERT ...)
* EXPLAIN
* CREATE/DROP INDEX
* BEGIN/COMMIT/ROLLBACK
* GROUP BY/HAVING
* ORDER BY/LIMIT/OFFSET
* Joins, UNION, INTERSECT etc

If you want one of the things that isn't supported, then pretty please send me a pull request. Implementing things is way easier when you don't have to implement them.

## Should I use it for my CouchDB instance running on the ISS and/or powering the life support machines for a cancer ward full of photogenic orphans?

Sweet isaacs, no. This code is about as raw as it gets. There are no tests and I don't even have any kind of fancy parse chain, just a big stack o' regular expressions. I got it to a point where it did all the things I needed and then released it into the wild.

While I can't think of a way that a SELECT could delete all your data, I'm not yet comfortable saying it's impossible, especially if you're on Windows, have strange locale settings, or sneeze really hard.

## How does it work?

In a word: slowly. Each select makes a CouchDB temporary view with a map function that only emits if your condition is true. Delete/Update does the same, plus an additional bulk query with the results. Insert is pretty fast, though.

Temporary views are basically performance catnip, so if you do one with a big database don't be surprised if couch starts drooling or tripping over its own feet. Above all, *do not build strings and send them to UnQL ever.* This is not a library for interacting with Couch from your code, just a way to run ad-hoc queries easily.

## CouchDB sucks. I only use Cassandra, but you've probably never heard of it. How about supporting other NoSQL data stores?

Good point, NoSQL hipster! I would love for this module to support things that aren't CouchDB. In fact, near as I can understand, that was the original point of the UnQL spec. If you want to volunteer to write the backend for another NoSQL store, get in touch - my email's on my GitHub profile page.

## I want to take your code, turn it into a web service, and sell it to Oracle for a billion dollars. Is that OK?

Sure. The code is MIT-licensed, so exploit your little heart out.
