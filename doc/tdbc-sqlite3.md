# tdbc::sqlite3

```tcl
package require tdbc::sqlite3

tdbc::sqlite3::connection create db sqlite.db

# -encoding utf-8
# -isolation readuncommitted | serializable
# -readonly
# -timeout

set stmt [db prepare {
  SELECT * FROM t WHERE name=:name
}] 

set resultset [$stmt execute [dict create name $name]]

$resultset columns
$resultset rowcount

do {
  $resultset nextrow -as lists|dicts row
  $resultset nextlist row
  $resultset nextdict row
} while [$resultset nextresults]

$resultset allrows ?-as lists|dicts? row

$resultset foreach ?-as lists|dicts? row {
   ...
}

$resultset close


$stmt foreach ?-as lists|dicts? row [dict create name $name] {
  ...
}

$stmt close
```
