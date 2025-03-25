
# get latest online version from online source
$latest_online_version=$(Invoke-WebRequest 'https://api.github.com/repos/OpenTTD/OpenTTD/releases/latest' | convertfrom-json | select -ExpandProperty name)
$latest_sha256=$(Invoke-WebRequest "https://factorio.com/download/sha256sums/" | grep "factorio_headless_x64_${latest_online_version}.tar.xz" | awk '{print $1}')

# get latest current version from buildinfo.json
$latest_current_version=$(Get-Content buildinfo.json | ConvertFrom-Json | gm -Type NoteProperty | sort name -Descending | select -ExpandProperty name -First 1)

echo "latest_online_version  = $latest_online_version"
echo "latest_current_version = $latest_current_version"

# check if online version is differetn from current
if ($latest_online_version -eq $latest_current_version){
  return "no new version"
}

# convert versions to semver
$latest_online_version_semver=[semver]$latest_online_version
$latest_current_version_semver=[semver]$latest_current_version

# get short version (major.minor)
$latest_online_version_short = "$($latest_online_version_semver.Major).$($latest_online_version_semver.Minor)"
$latest_current_version_short = "$($latest_current_version_semver.Major).$($latest_current_version_semver.Minor)"

echo "latest_online_version_short  = $latest_online_version_short"
echo "latest_current_version_short = $latest_current_version_short"

$tmpfile="c:\tmp\temp.json"

# Remove latest tag
cp buildinfo.json $tmpfile

$temp = Get-Content $tmpfile | convertfrom-json

# remote latest, stable, major version, major.minor version from existing tags
foreach($current_version_name in $temp | gm -Type NoteProperty | select -ExpandProperty name){
  $temp.$current_version_name.tags = $temp.$current_version_name.tags | `
    ? {$_ -ne "latest"} | `
    ? {$_ -ne "stable"} | `
    ? {$_ -ne "$($latest_online_version_semver.Major)"} | `
    ? {$_ -ne "$latest_online_version_short"}
}

# add new entry to json
$temp | Add-Member -MemberType NoteProperty -Name $latest_online_version_semver -Value @{
  tags = @(
    "latest"
    "stable"
    "$($latest_online_version_semver.Major)"
    "$latest_online_version_short"
    "$latest_online_version_semver"
  )
}

# sort json and write to buildinfo.json
$temp | Select-Object ($temp | Get-Member -MemberType NoteProperty | sort name -Descending).Name | ConvertTo-Json -Depth 10 | Out-File buildinfo.json -Encoding utf8


readme_tags=$(jq --sort-keys 'keys[]' buildinfo.json | tac | (while read -r line
do
  tags="$tags\n* "$(jq --sort-keys ".$line.tags | sort | .[]" buildinfo.json | sed 's/"/`/g' | sed ':a; /$/N; s/\n/, /; ta')
done && printf "%s\n\n" "$tags"))

perl -i -0777 -pe "s/<!-- start autogeneration tags -->.+<!-- end autogeneration tags -->/
<!-- start autogeneration tags -->$readme_tags<!-- end autogeneration tags -->/s" README.md


# Replace VERSION and SHA256 args in docker-compose.yaml with latest stable values.
docker_compose_path="docker/docker-compose.yml"
sov="VERSION=${stable_online_version}" yq -i '.services.factorio.build.args[0] = env(sov)' "$docker_compose_path"
sha="SHA256=${stable_sha256}" yq -i '.services.factorio.build.args[1] = env(sha)' "$docker_compose_path"

git config user.name github-actions[bot]
git config user.email 41898282+github-actions[bot]@users.noreply.github.com

git add buildinfo.json
git add README.md
git add docker/docker-compose.yml
git commit -a -m "Auto update to current version: ${current_online_version}"

git tag -f latest
git push
git push origin --tags -f
