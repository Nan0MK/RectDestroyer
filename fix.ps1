$root = "C:\Users\Nan0MK\DEV\CLONE\RectDestroyer\src\levels"

function Row($s, $w) {
  if ($s.Length -lt $w) { $s = $s + (" " * ($w - $s.Length)) } else { $s = $s.Substring(0, $w) }
  return $s
}

function OverwriteCell($lines, $y, $x, $ch) {
  $l = $lines[$y].ToCharArray()
  $l[$x] = $ch
  $lines[$y] = -join $l
}

function TemplateWolf($w, $h) {
  $lines = New-Object System.Collections.ArrayList
  for ($y = 0; $y -lt $h; $y++) { [void]$lines.Add(" " * $w) }
  for ($x = 0; $x -lt $w; $x++) {
    $t = if ($x % 4 -eq 0) { "T" } elseif ($x % 4 -eq 2) { "S" } else { "T" }
    OverwriteCell $lines 0 $x $t
    OverwriteCell $lines ($h - 1) $x $t
  }
  for ($y = 1; $y -lt $h - 1; $y++) {
    OverwriteCell $lines $y 0 "T"
    OverwriteCell $lines $y ($w - 1) "T"
  }
  for ($y = 1; $y -lt $h - 1; $y++) {
    for ($x = 1; $x -lt $w - 1; $x++) {
      OverwriteCell $lines $y $x "U"
    }
  }
  return ,$lines.ToArray()
}

function TemplateFrame($w, $h) {
  $lines = TemplateWolf $w $h
  for ($y = 1; $y -lt $h - 1; $y++) {
    OverwriteCell $lines $y 1 "S"
    OverwriteCell $lines $y ($w - 2) "S"
  }
  for ($x = 1; $x -lt $w - 1; $x++) {
    OverwriteCell $lines 1 $x "S"
    OverwriteCell $lines ($h - 2) $x "S"
  }
  return $lines
}

function TemplateChecker($w, $h) {
  $lines = New-Object System.Collections.ArrayList
  for ($y = 0; $y -lt $h; $y++) {
    $r = ""
    for ($x = 0; $x -lt $w; $x++) {
      if (($x + $y) % 2 -eq 0) { $r += "U" } else { $r += " " }
    }
    [void]$lines.Add($r)
  }
  return ,$lines.ToArray()
}

function PlaceSymbol($lines, $x, $y, $s, $char) {
  $r = $lines[$y].ToCharArray()
  for ($i = 0; $i -lt $s.Length; $i++) { $r[$x + $i] = $char }
  $lines[$y] = -join $r
}

# --- levels 21..40: same voice as 19 and 20 ---
$palette = @("F","M","O","T","S","U","X")
for ($i = 21; $i -le 40; $i++) {
  $w = 19 + ($i - 21) % 3
  $h = 9 + ($i - 21) % 3
  $lines = TemplateFrame $w $h
  # corners and sprinkles
  OverwriteCell $lines 1 1 "F"
  OverwriteCell $lines 1 ($w - 2) "F"
  OverwriteCell $lines ($h - 2) 1 "F"
  OverwriteCell $lines ($h - 2) ($w - 2) "F"
  for ($x = 2; $x -lt $w - 2; $x += 2) {
    OverwriteCell $lines 2 $x ($palette[($x + $i) % 7])
    OverwriteCell $lines ($h - 3) $x ($palette[($i + $x) % 7])
  }
  # center feature
  $cx = [int]($w / 2)
  $cy = [int]($h / 2)
  if ($i % 4 -eq 0) {
    OverwriteCell $lines $cy $cx "X"
  } elseif ($i % 4 -eq 1) {
    OverwriteCell $lines $cy ($cx - 1) "M"
    OverwriteCell $lines $cy $cx "M"
  } elseif ($i % 4 -eq 2) {
    OverwriteCell $lines $cy $cx "O"
    OverwriteCell $lines $cy ($cx - 1) "O"
    OverwriteCell $lines $cy ($cx + 1) "O"
  } else {
    OverwriteCell $lines $cy $cx "U"
    OverwriteCell $lines ($cy - 1) $cx "U"
    OverwriteCell $lines ($cy + 1) $cx "U"
    OverwriteCell $lines $cy ($cx - 1) "U"
    OverwriteCell $lines $cy ($cx + 1) "U"
  }
  Out-File -FilePath (Join-Path $root "lvl$i.txt") -Encoding ascii -InputObject ($lines -join "`n")
}

# --- levels 41..100: denser, harder ---
for ($i = 41; $i -le 100; $i++) {
  $w = 21
  $h = 13
  $lines = TemplateFrame $w $h
  # replace interior with U field (already), add threat density by level
  $density = [Math]::Min(10, 3 + [int](($i - 41) / 8))
  for ($k = 0; $k -lt $density; $k++) {
    $x = 2 + (($i * 7 + $k * 5) % ($w - 4))
    $y = 2 + (($i * 3 + $k * 3) % ($h - 4))
    $symbol = switch (($k + $i) % 4) {
      0 { "O" }
      1 { "X" }
      2 { "S" }
      default { "T" }
    }
    OverwriteCell $lines $y $x $symbol
  }
  # center anchor
  $cx = [int]($w / 2)
  $cy = [int]($h / 2)
  if ($i % 5 -eq 0) {
    PlaceSymbol $lines ($cx - 2) $cy "XXXXX" "X"
  } elseif ($i % 5 -eq 1) {
    PlaceSymbol $lines ($cx - 2) $cy "OOOOO" "O"
  } elseif ($i % 5 -eq 2) {
    PlaceSymbol $lines ($cx - 2) $cy "SSSSS" "S"
  } elseif ($i % 5 -eq 3) {
    PlaceSymbol $lines ($cx - 2) $cy "TTTTT" "T"
  }
  Out-File -FilePath (Join-Path $root "lvl$i.txt") -Encoding ascii -InputObject ($lines -join "`n")
}
