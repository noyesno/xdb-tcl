# xdb-tcl

`xdb-tcl` try to be a SQLite server for Tcl.

  * Tcl client can query SQLite database on remote host.
  * Database connection on remote host is persistent to improve performance. 
  * Query result is cached to improve performance.
  * Allow result filter on remote host to save network bandwidth.

## Start the Server

```sh
xdb-tcl.kit 6789
```

## Client Side Quick Example

Basic example is as below:

```tcl
package require xdb-tcl

set xdb [xdb-tcl::connect $remote_host $remote_port]

$xdb -print
$xdb use /path/to/sqlite.db
$xdb query {
  SELECT * FROM test_table
}
```

### Bind Variable

```tcl
$xdb query {
  SELECT * FROM test_table WHERE name=$name AND age>$age
} [list name $name age $age]
```
