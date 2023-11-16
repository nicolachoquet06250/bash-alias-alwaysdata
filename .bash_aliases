#!/bin/bash

function alwaysdata() {
  #  Gestion des fatales
  if [[ "${ALIASES_FRAMEWORK_DEFINED}" == "" ]];then
    echo ""
    echo "❌ Le framework d'aliases n'est pas importé !"
    echo ""
    return
  fi

  #  Création d'un helper pour le logo
  function logo() {
    framework_title -t "Alwaysdata" \
      -f "$(framework_figlet_font_path "Big%20Money-se")" \
      -st -sb
  }

  # parsing des flags
  eval "$(framework_flag)"

  #  Gestion des fatales
  if [[ "${ALWAYSDATA_API_KEY}" == "" ]];then
    logo

    framework_error_message "Vous devez définir une clé d'API de Alwaysdata !"

    # shellcheck disable=SC2034
    declare -a doc=(
      "Aller sur $(framework_link "https://admin.alwaysdata.com/token/add/")"
      "Remplire le formulaire"
      "Ajouter \\\"export ALWAYSDATA_API_KEY=<votre-cle>\\\" à la fin du fichier $(framework_link "${HOME}/.bashrc")"
    )
    eval "$(framework_generate_doc doc)"

    echo ""
    return
  fi

  # Définition des variables
  assets="${HOME}/aliases/assets"
  api_url="https://api.alwaysdata.com/v1"

  sites_file_name="alwaysdata.sites.json"
  databases_file_name="alwaysdata.databases.json"

  # Création du répertoire d'assets pour les fonts du titre
  mkdir -p "${assets}"

  # Définition des fonctions helpers
  function isDebug() {
    flag "debug" "d"
  }

  function isForceReFetch() {
    flag "force" "f"
  }

  function generate_json_file_content() {
      curl_result="$1"

      echo "{\"results\": ${curl_result}, \"creation_timestamp\": $(timestamp), \"expires_in\": 86400}"
  }

  function fetch_sites() {
    curl_result=$(curl -X GET \
      -s \
      --basic --user "${ALWAYSDATA_API_KEY}:" \
      "${api_url}/site/")
    if [[ "${curl_result}" =~ "\"IP address not allowed\"" ]];then
      framework_error_message "Alwaysdata API error: ${curl_result}"
      return
    fi
    generate_json_file_content "${curl_result}" > "${assets}/${sites_file_name}"
  }

  function sites() {
      cat "${assets}/${sites_file_name}"
  }

  function re_save_sites() {
    if [[ "$1" == "-f" ]] || \
       [[ "$1" == "--force" ]] || \
       [[ "$(flag "force" "f")" == true ]] || \
       [[ ! -f "${assets}/${sites_file_name}" ]]
    then
      # shellcheck disable=SC2154
      [[ "$(isDebug)" == true ]] && echo "reload sites"
      fetch_sites
    else
      json=$(sites)
      creation_timestamp=$(jq -r ".creation_timestamp" <<<"$json")
      expires_in=$(jq -r ".expires_in" <<<"$json")

      if [[ $(timestamp) -gt $((creation_timestamp + expires_in)) ]];then
        # shellcheck disable=SC2154
        [[ "$(isDebug)" == true ]] && echo "reload sites"
        fetch_sites
      fi
    fi
  }

  function fetch_databases() {
    curl_result=$(curl -X GET \
      -s \
      --basic --user "${ALWAYSDATA_API_KEY}:" \
      "${api_url}/database/")
    if [[ "${curl_result}" =~ "\"IP address not allowed\"" ]];then
      framework_error_message "Alwaysdata API error: ${curl_result}"
      return
    fi
    generate_json_file_content "${curl_result}" > "${assets}/${databases_file_name}"
  }

  function databases() {
      cat "${assets}/${databases_file_name}"
  }

  function re_save_databases() {
    if [[ "$1" == "-f" ]] || \
       [[ "$1" == "--force" ]] || \
       [[ "$(flag "force" "f")" == true ]] || \
       [[ ! -f "${assets}/${databases_file_name}" ]]
    then
      # shellcheck disable=SC2154
      [[ "$(isDebug)" == true ]] && echo "reload databases"
      fetch_databases
    else
      json=$(sites)
      creation_timestamp=$(jq -r ".creation_timestamp" <<<"$json")
      expires_in=$(jq -r ".expires_in" <<<"$json")

      if [[ $(timestamp) -gt $((creation_timestamp + expires_in)) ]];then
        # shellcheck disable=SC2154
        [[ "$(isDebug)" == true ]] && echo "reload databases"
        fetch_databases
      fi
    fi
  }

  function generate_flags_doc() {
    cmd="$1"
    cmd_alias="$2"
    type="$3"
    local -n flags=$4

    echo "alwaysdata ${cmd} --type ${type} \\"

    for key in "${!flags[@]}";do
      [[ "${flags[$key]}" == "" ]] && \
        echo " --${key} <${key}> \\" || \
        echo " [--${key} <${key}=${flags[$key]}>] \\"
    done

    echo " "

    echo "alwaysdata ${cmd_alias} --type ${type} \\"

    for key in "${!flags[@]}";do
      [[ "${flags[$key]}" == "" ]] && \
        echo " --${key} <${key}> \\" || \
        echo " [--${key} <${key}=${flags[$key]}>] \\"
    done
  }

  function generate_json_request_body() {
    local -n data=$1

    length=${#data[@]}
    i=0
    _json="{ "
    for k in "${!data[@]}";do
      key_length=${#k}
      if [[ "${k:$((key_length-1)):1}" =~ "s" ]] && [[ "${data[$k]}" =~ "," ]];then
        sparts=$(echo "${data[$k]}" | tr "," "\n")
        IFS=$'\n'
        tmp="["
        read -rd '' -a parts <<<"$sparts"
        l=${#parts[@]}
        _i=0
        for part in "${parts[@]}";do
          [[ "${part:0:8}" == "https://" ]] && part="${part:8:${#part}}"
          [[ "${part:0:7}" == "http://" ]] && part="${part:7:${#part}}"
          tmp+="\"${part}\""
          [[ $_i -lt $((l-1)) ]] && tmp+=", "
          _i=$((_i+1))
        done
        tmp+="]"
        data[$k]="${tmp}"
      fi

      {
        [[ "${data[$k]}" =~ ^([0-9]+\.?[0-9]*)$ ]] || \
        [[ "${data[$k]}" =~ ^(true|false)$ ]] || \
        [[ "${data[$k]}" =~ ^(\[.*\])$ ]]
      } &&
        _json+="\"${k}\": ${data[$k]}" ||
        _json+="\"${k}\": \"${data[$k]}\""

      [[ $i -lt $((length-1)) ]] && _json+=", "
      i=$((i+1))
    done
    _json+=" }"

    echo "${_json}"
  }

  logo

  #  Re enregistrement des sites si besoin
  first_api_result=$(re_save_sites)

  #  Gestion des fatales
  if [[ "${first_api_result}" =~ "Alwaysdata API error" ]];then
    echo "${first_api_result}"
    return;
  fi

  [[ "$(isForceReFetch)" == true ]] && re_save_sites

  json="$(sites)"

  # Définition des fonctions de sous commandes et défiinition des sous commandes
  function help() {
      command_lines=(
        "alwaysdata site:list [-s|--search [<key>(=name|id)=|!=|=~|!=~]<value>(name|id)]"
        " - Si la clé n'est pas définie et que la valeur indiquée est un nombre alors la clé sera 'id', "
        " sinon ce sera 'name'"
        " - Opérateurs pris en charges :"
        "   = -> ... est égual à ..."
        "   != -> ... est différent de ..."
        "   =~ -> ... contient ..."
        "   !=~ -> ... ne contient pas ..."
        "⬆️  (alias) alwaysdata s:l [-s|--search [<key>(=name)=]<value>(name/id)]"
        ""
        "alwaysdata site:create [--help|-h|help] --type <type=php|apache_custom|nodejs|deno> ..."
        "⬆️  (alias) alwaysdata s:c [--help|-h|help] --type <type=php|apache_custom|nodejs|deno> ..."
        ""
        "alwaysdata site:delete --id <id>"
        "⬆️  (alias) alwaysdata s:d --id <id>"
        ""
        "alwaysdata site:restart --id <id>"
        "⬆️  (alias) alwaysdata s:r --id <id>"
        ""
        "alwaysdata database:list [-s|--search [<key>(=name|id)=|!=|=~|!=~]<value>(name|id)] [--id <id>]"
        " - Si la clé n'est pas définie et que la valeur indiquée est un nombre alors la clé sera 'id', "
        " sinon ce sera 'name'"
        " - Opérateurs pris en charges :"
        "   = -> ... est égual à ..."
        "   != -> ... est différent de ..."
        "   =~ -> ... contient ..."
        "   !=~ -> ... ne contient pas ..."
        "⬆️  (alias) alwaysdata db:l [-s|--search [<key>(=name)=]<value>(name/id)] [--id <id>]"
        ""
        "alwaysdata database:create [--help|-h|help] --type <type=COUCHDB|MONGODB|MYSQL|POSTGRESQL|RABBITMQ> ..."
        "⬆️  (alias) alwaysdata db:c [--help|-h|help] --type <type=COUCHDB|MONGODB|MYSQL|POSTGRESQL|RABBITMQ> ..."
        ""
        "alwaysdata database:delete --id <id>"
        "⬆️  (alias) alwaysdata db:d --id <id>"
      )

      framework_create_help "alwaysdata" "${command_lines[@]}"
  }
  eval "$(framework_sub_command -n "help")"

  function site_list() {
    re_save_sites
    json="$(sites)"

    mapfile -t names < <(jq -r '.results[] | .name' <<<"$json")
    mapfile -t ids < <(jq -r '.results[] | .id' <<<"$json")
    mapfile -t ssl_forces < <(jq -r '.results[] | .ssl_force' <<<"$json")
    mapfile -t addresses < <(jq -r '.results[] | .addresses | @csv' <<<"$json")

    search=$(flag "search" "s")
    if [[ "${search}" != false ]];then
      operator="=="
      key="name"
      value="\"${search}\""
      if [[ "${search}" =~ ^([0-9]+)$ ]];then
        key="id"
        value="${search}"
      fi

      if [[ "${search}" =~ "!=" ]]; then
        sparts=$(echo "${search}" | tr "!=" "\n")
        IFS=$'\n'
        read -rd '' -a parts <<<"$sparts"
        operator="!="
        key="${parts[0]}"
        value="\"${parts[1]}\""
      elif [[ "${search}" =~ "!=~" ]]; then
        sparts=$(echo "${search}" | tr "!=~" "\n")
        IFS=$'\n'
        read -rd '' -a parts <<<"$sparts"
        operator="!=~"
        key="${parts[0]}"
        value="\"${parts[1]}\""
      elif [[ "${search}" =~ "=~" ]]; then
        sparts=$(echo "${search}" | tr "=~" "\n")
        IFS=$'\n'
        read -rd '' -a parts <<<"$sparts"
        operator="=~"
        key="${parts[0]}"
        value="\"${parts[1]}\""
      elif [[ "${search}" =~ "=" ]];then
        sparts=$(echo "${search}" | tr "=" "\n")
        IFS=$'\n'
        read -rd '' -a parts <<<"$sparts"
        key="${parts[0]}"
        value="\"${parts[1]}\""
      fi

      if [[ "${key}" == "name" ]] && [[ "${value}" == "\"Unnamed site\"" ]];then
        value="\"\""
      fi

      select=".${key}${operator}${value}"
      if [[ "${operator}" == "=~" ]];then
        select=".${key} | @csv | contains(${value})"
      elif [[ "${operator}" == "!=~" ]];then
        select=".${key} | @csv | contains(${value}) | not"
      fi

      select="select(${select})"

      mapfile -t names < <(jq -r ".results[] | ${select} | .name" <<<"$json")
      mapfile -t ids < <(jq -r ".results[] | ${select} | .id" <<<"$json")
      mapfile -t ssl_forces < <(jq -r ".results[] | ${select} | .ssl_force" <<<"$json")
      mapfile -t addresses < <(jq -r ".results[] | ${select} | .addresses | @csv" <<<"$json")
    fi

    length=${#names[@]}
    for (( i=0; i<length; i++ ))
    do
      id="${ids[i]}"
      name="${names[i]}"
      urls="${addresses[i]}"
      ssl_force=${ssl_forces[i]}

      if [[ "${name}" != "" ]];then
        echo -n "${name}"
      else
        echo -n "Unnamed site"
      fi

      echo " (${id}): "

      for addr in $(echo "$urls" | tr "," "\n")
      do
        if [[ ${ssl_force} == true ]];then
          echo "> [https://$(echo "$addr" | cut -d "\"" -f 2)]"
        elif [[ ${ssl_force} == false ]];then
          echo "> [http://$(echo "$addr" | cut -d "\"" -f 2)]"
        fi
      done
    done
  }
  eval "$(framework_sub_command -n "site:list" -s "s:l")"

  function site_restart() {
    json="$(sites)"
    id=$(flag "id")

    mapfile -t ids < <(jq -r ".results[] | select(.id==${id}) | .id" <<<"$json")
    mapfile -t names < <(jq -r ".results[] | select(.id==${id}) | .name" <<<"$json")
    mapfile -t ssl_forces < <(jq -r ".results[] | select(.id==${id}) | .ssl_force" <<<"$json")
    mapfile -t addresses < <(jq -r ".results[] | select(.id==${id}) | .addresses | @csv" <<<"$json")

    if [[ "${#ids[@]}" == "1" ]];then
      curl  -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -s \
            --basic --user "${ALWAYSDATA_API_KEY}:" \
            -X POST \
            "${api_url}/site/${id}/restart/"

      name="${names[0]}"
      if [[ "${names[0]}" == "" ]];then
        urls=$(echo "${addresses[0]}" | tr "," "\n")
        ssl_force=${ssl_forces[0]}

        name="Unnamed site"
        if [[ ${ssl_force} == true ]];then
          name="https://$(echo "${urls[0]}" | cut -d "\"" -f 2)"
        elif [[ ${ssl_force} == false ]];then
          name="http://$(echo "${urls[0]}" | cut -d "\"" -f 2)"
        fi
      fi

      framework_success_message "site ${name} restarted"
    else
      framework_error_message "site with id ${id} not found"
    fi
  }
  eval "$(framework_sub_command -n "site:restart" -s "s:r")"

  function site_create() {
    t=$(flag "type" "t")
    types=("php" "apache_custom" "nodejs" "deno")
    command_lines=()

    # shellcheck disable=SC2034
    declare -A flags_php=(
      ['path']="/www/"
      ['php_version']="''"
      ['php_ini']="''"
      ['environment']="''"
      ['vhost_additional_directives']="''"
      ['ssl_force']="false"
      ['max_idle_time']="1800"
      ['path_trim']="false"
      ['waf_profile']="null"
      ['waf_excluded_rules']="[]"
      ['waf_excluded_paths']="[]"
      ['waf_excluded_ips']="[]"
      ['cache_enabled']="false"
      ['cache_ttl']="3600"
      ['log_type']="STANDARD"
      ['log_file']="null"
      ['log_format']="null"
      ['addresses']=""
      ['annotation']="''"
    )

    # shellcheck disable=SC2034
    declare -A flags_apache_custom=(
      ['global_directives']="null"
      ['vhost_directives']=""
      ['vhost_additional_directives']="null"
      ['ssl_force']="false"
      ['max_idle_time']="1800"
      ['path_trim']="false"
      ['waf_profile']="null"
      ['waf_excluded_rules']="[]"
      ['waf_excluded_paths']="[]"
      ['waf_excluded_ips']="[]"
      ['cache_enabled']="false"
      ['cache_ttl']="3600"
      ['log_type']="STANDARD"
      ['log_file']="null"
      ['log_format']="null"
      ['addresses']=""
      ['annotation']="''"
    )

    # shellcheck disable=SC2034
    declare -A flags_nodejs=(
      ['command']=""
      ['working_directory']="/home/my-account"
      ['environment']="''"
      ['nodejs_version']="''"
      ['signal_reload']="null"
      ['ssl_force']="false"
      ['max_idle_time']="1800"
      ['path_trim']="false"
      ['waf_profile']="null"
      ['waf_excluded_rules']="[]"
      ['waf_excluded_paths']="[]"
      ['waf_excluded_ips']="[]"
      ['cache_enabled']="false"
      ['cache_ttl']="3600"
      ['log_type']="STANDARD"
      ['log_file']="null"
      ['log_format']="null"
      ['addresses']=""
      ['annotation']="''"
    )

    # shellcheck disable=SC2034
    declare -A flags_deno=(
      ['command']=""
      ['working_directory']="/home/my-account"
      ['environment']="''"
      ['deno_version']="''"
      ['signal_reload']="null"
      ['ssl_force']="false"
      ['max_idle_time']="1800"
      ['path_trim']="false"
      ['waf_profile']="null"
      ['waf_excluded_rules']="[]"
      ['waf_excluded_paths']="[]"
      ['waf_excluded_ips']="[]"
      ['cache_enabled']="false"
      ['cache_ttl']="3600"
      ['log_type']="STANDARD"
      ['log_file']="null"
      ['log_format']="null"
      ['addresses']=""
      ['annotation']="''"
    )

    if {
      [[ "$(flag "help" "h")" == true ]] ||
      [[ "$1" == "" ]]
    } && [[ "${t}" == false ]];then
      cmp=0
      length=${#types[@]}
      for t in "${types[@]}";do
        cmp=$((cmp + 1))
        IFS=$'\n'
        read -rd '' -a arr <<<"$(generate_flags_doc "site:create" "s:c" "${t}" flags_"$t")"
        command_lines+=("${arr[@]}")
        [[ $cmp -lt $length ]] && command_lines+=("")
      done

      framework_create_help "alwaysdata site:create" "${command_lines[@]}"

      return
    else
      is_type_valid=0
      if [[ "${t}" != false ]];then
        for type in "${types[@]}";do
          if [[ "${type}" == "$t" ]];then
            is_type_valid=1
            break
          fi
        done
      fi

      if [[ "${is_type_valid}" == "1" ]];then
        if {
          [[ "$(flag "help" "h")" == true ]] ||
          [[ "$3" == "" ]]
        };then
          IFS=$'\n'
          read -rd '' -a current_flags <<<"$(generate_flags_doc "site:create" "s:c" "${t}" flags_"${t}")"

          if [[ "${#current_flags[@]}" != "0" ]];then
            framework_create_help "alwaysdata site:create --type $2" "${current_flags[@]}"
          fi

          return;
        else
          #       Gestion des flags manquants
          type=$(flag "type")
          array_name="flags_${type}"
          # shellcheck disable=SC2178
          declare -n current_flags=$array_name

          missing_flags=0
          for flag in "${!current_flags[@]}";do
            if [[ "$(flag "${flag}")" == false ]] && [[ "${current_flags[$flag]}" == "" ]]
            then
              echo "⚠️  --${flag} flag is required"
              missing_flags=1
            fi
          done

          if [[ "${missing_flags}" == "1" ]];then
            framework_error_message "flags missing"
            return;
          fi

          args=("${@}")
          declare -A final_data=(['type']="${type}")

          for flag in "${!current_flags[@]}";do
            index=0
            for arg in "${args[@]}";do
              if [[ "${arg}" == "--${flag}" ]];then
                flag_name="${args[$index]:2:${#args[$index]}}"
                final_data+=([$flag_name]="$(flag "${flag_name}")")
                break
              else
                index=$((index+1))
              fi
            done
          done

          if [[ "${final_data['addresses']}" =~ "https://" ]];then
            final_data+=(['ssl_force']="true")
          fi
        fi

        s_curl_result=$(curl  -H "Content-Type: application/json" \
                -H "Accept: application/json" \
                -s \
                --basic --user "${ALWAYSDATA_API_KEY}:" \
                -X POST \
                -d "$(generate_json_request_body final_data)" \
                -i \
                "${api_url}/site/")

        IFS=$'\n'
        read -rd '' -a curl_result <<<"$s_curl_result"

        IFS=$' '
        read -rd '' -a curl_result_status <<<"${curl_result[0]}"
        IFS=$''

        status_code=${curl_result_status[1]}

        if [[ "${status_code}" == "400" ]];then
          framework_error_message "Alwaysdata API error: Le site que vous essayez de créer existe déjà"
           #         TODO : afficher les url pour donner plus d'indications à l'utilisateur

          return;
        fi

        if [[ "${status_code:0:2}" == "20" ]];then
          framework_success_message "Le site à bien été créé"
          re_save_sites --force
        else
          framework_error_message "Alwaysdata API error: Une erreur est survenue lors de la création du site"
        fi
      fi
    fi
  }
  eval "$(framework_sub_command -n "site:create" -s "s:c")"

  function site_delete() {
    id=$(flag "id")

    if [[ "${id}" == false ]];then
      framework_error_message "Vous devez renseigner le flag --id !"
      return;
    fi

    s_curl_result=$(
      curl -H "Content-Type: application/json" \
           -H "Accept: application/json" \
           -s \
           -i \
           --basic --user "${ALWAYSDATA_API_KEY}:" \
           -X DELETE \
           "${api_url}/site/${id}/"
    )

    IFS=$'\n'
    read -rd '' -a curl_result <<<"$s_curl_result"

    IFS=$' '
    read -rd '' -a curl_result_status <<<"${curl_result[0]}"
    IFS=$''

    status_code=${curl_result_status[1]}

    if [[ "${status_code}" == "400" ]];then
      framework_error_message "Alwaysdata API error: ${s_curl_result}"

      return;
    fi

    if [[ "${status_code:0:2}" == "20" ]];then
      framework_success_message "Le site à bien été supprimé"
      re_save_sites --force
    else
      framework_error_message "Alwaysdata API error: Une erreur est survenue lors de la création du site"
    fi
  }
  eval "$(framework_sub_command -n "site:delete" -s "s:d")"

  function database_list() {
    re_save_databases
    id=$(flag "id")

    if [[ "${id}" != false ]];then
      # shellcheck disable=SC2178
      curl_result=$(
        curl -X GET --silent -b --verbose \
             -H "X-Content-Type-Options: nosniff" \
             --basic --user "${ALWAYSDATA_API_KEY}:" \
             "${api_url}/database/?id=${id}"
      )
      if [[ "${curl_result[*]}" =~ "\"IP address not allowed\"" ]];then
        framework_error_message "Alwaysdata API error: ${curl_result[*]}"
        return
      fi

      json="${curl_result[0]}"
      declare -A arr=()

      mapfile -t obj < <(jq -r '.[0]' <<<"${json}")
      mapfile -t json_object_keys < <(jq -r 'keys_unsorted[]' <<<"${obj[@]}")

      for key in "${json_object_keys[@]}";do
        mapfile -t item < <(jq -r ".${key}" <<<"${obj[@]}")

        if [[ "${item[*]:0:1}" == "[" ]] || [[ "${item[*]:0:1}" == "{" ]];then
          mapfile -t items_keys < <(jq -r 'keys_unsorted[]' <<<"${item[@]}")
          _item=""

          for k in "${items_keys[@]}";do
            mapfile -t v < <(jq -r ".\"${k}\"" <<<"${item[@]}")
            _item+="${k}:${v[*]},"
          done

          item_length=${#_item}

          arr["${key}"]="${_item:0:$((item_length-1))}"
        else
          arr["${key}"]="${item[*]}"
        fi
      done

      echo "Type : ${arr['type']}"
      echo "Name : ${arr['name']}"
      echo "Id : ${arr['id']}"
      [[ "${arr['id']}" == true ]] && echo "Is public" || echo "Is private"
      api_url_length=${#api_url}
      end=$((api_url_length-3))
      echo "Href : ${api_url:0:$end}${arr['href']}"
      echo "Annotation : ${arr['annotation']}"
      echo "Permissions :"
      IFS=$','
      read -rd '' -a permissions <<<"${arr['permissions']}"
      for permission in "${permissions[@]}";do
        # shellcheck disable=SC2001
        permission=$(echo "$permission" | sed -e 's/\n*$//g')
        IFS=$':'
        read -rd '' -a permission_parts <<<"${permission}"

        # shellcheck disable=SC2001
        echo " > [${permission_parts[0]}] $(echo "${permission_parts[1]}" | sed -e 's/\n*//g')"
      done

      return;
    fi

    json="$(databases)"

    mapfile -t names < <(jq -r '.results[] | .name' <<<"$json")
    mapfile -t ids < <(jq -r '.results[] | .id' <<<"$json")
    mapfile -t types < <(jq -r '.results[] | .type' <<<"$json")

    search=$(flag "search" "s")
    if [[ "${search}" != false ]];then
      operator="=="
      key="name"
      value="\"${search}\""
      if [[ "${search}" =~ ^([0-9]+)$ ]];then
        key="id"
        value="${search}"
      fi

      if [[ "${search}" =~ "!=" ]]; then
        sparts=$(echo "${search}" | tr "!=" "\n")
        IFS=$'\n'
        read -rd '' -a parts <<<"$sparts"
        operator="!="
        key="${parts[0]}"
        value="\"${parts[1]}\""
      elif [[ "${search}" =~ "!=~" ]]; then
        sparts=$(echo "${search}" | tr "!=~" "\n")
        IFS=$'\n'
        read -rd '' -a parts <<<"$sparts"
        operator="!=~"
        key="${parts[0]}"
        value="\"${parts[1]}\""
      elif [[ "${search}" =~ "=~" ]]; then
        sparts=$(echo "${search}" | tr "=~" "\n")
        IFS=$'\n'
        read -rd '' -a parts <<<"$sparts"
        operator="=~"
        key="${parts[0]}"
        value="\"${parts[1]}\""
      elif [[ "${search}" =~ "=" ]];then
        sparts=$(echo "${search}" | tr "=" "\n")
        IFS=$'\n'
        read -rd '' -a parts <<<"$sparts"
        key="${parts[0]}"
        value="\"${parts[1]}\""
      fi

      if [[ "${key}" == "name" ]] && [[ "${value}" == "\"Unnamed site\"" ]];then
        value="\"\""
      fi

      select=".${key}${operator}${value}"
      if [[ "${operator}" == "=~" ]];then
        select=".${key} | contains(${value})"
      elif [[ "${operator}" == "!=~" ]];then
        select=".${key} | contains(${value}) | not"
      fi

      select="select(${select})"

      mapfile -t names < <(jq -r ".results[] | ${select} | .name" <<<"$json")
      mapfile -t ids < <(jq -r ".results[] | ${select} | .id" <<<"$json")
      mapfile -t types < <(jq -r ".results[] | ${select} | .type" <<<"$json")
    fi

    length=${#names[@]}
    for (( i=0; i<length; i++ ));do
      id="${ids[i]}"
      name="${names[i]}"
      type="${types[i]}"

      echo "${name} (${id}): ${type}"
    done
  }
  eval "$(framework_sub_command -n "database:list" -s "db:l")"

  function database_create() {
    t=$(flag "type" "t")
    types=("COUCHDB" "MONGODB" "MYSQL" "POSTGRESQL" "RABBITMQ")
    command_lines=()

    # shellcheck disable=SC2034
    declare -A flags_COUCHDB=(
      ['is_public']="false"
      ['name']="nicolas-choquet_"
      ['permissions']=""
      ['annotation']="''"
    )

    # shellcheck disable=SC2034
    declare -A flags_MONGODB=(
      ['name']="nicolas-choquet_"
      ['permissions']=""
      ['annotation']="''"
    )

    # shellcheck disable=SC2034
    declare -A flags_MYSQL=(
      ['name']="nicolas-choquet_"
      ['permissions']=""
      ['annotation']="''"
    )

    # shellcheck disable=SC2034
    declare -A flags_POSTGRESQL=(
      ['extensions']="null"
      ['locale']="en_US.utf8"
      ['name']="nicolas-choquet_"
      ['permissions']=""
      ['annotation']="''"
    )

    # shellcheck disable=SC2034
    declare -A flags_RABBITMQ=(
      ['name']="nicolas-choquet_"
      ['permissions']=""
      ['annotation']="''"
    )

    if {
      [[ "$(flag "help" "h")" == true ]] ||
      [[ "$1" == "" ]]
    } && [[ "${t}" == false ]];then
      cmp=0
      length=${#types[@]}
      for t in "${types[@]}";do
        cmp=$((cmp + 1))
        IFS=$'\n'
        read -rd '' -a arr <<<"$(generate_flags_doc "database:create" "db:c" "${t}" flags_"$t")"
        command_lines+=("${arr[@]}")
        [[ $cmp -lt $length ]] && command_lines+=("")
      done

      framework_create_help "alwaysdata database:create" "${command_lines[@]}"

      return
    else
      is_type_valid=0
      if [[ "${t}" != false ]];then
        for type in "${types[@]}";do
          if [[ "${type}" == "$t" ]];then
            is_type_valid=1
            break
          fi
        done
      fi

      if [[ "${is_type_valid}" == "1" ]];then
        if {
          [[ "$(flag "help" "h")" == true ]] ||
          [[ "$3" == "" ]]
        };then
          IFS=$'\n'
          read -rd '' -a current_flags <<<"$(generate_flags_doc "database:create" "db:c" "${t}" flags_"${t}")"

          if [[ "${#current_flags[@]}" != "0" ]];then
            framework_create_help "alwaysdata database:create --type ${t}" "${current_flags[@]}"
          fi

          return;
        else
    #     Gestion des flags manquants
          type=$(flag "type")
          array_name="flags_${type}"
          # shellcheck disable=SC2178
          declare -n current_flags=$array_name

          missing_flags=0
          for flag in "${!current_flags[@]}";do
            if {
              [[ "$(flag "${flag}")" == false ]] &&
              [[ "${current_flags[$flag]}" == "" ]]
            };then
              echo "⚠️  --${flag} flag is required"
              missing_flags=1
            fi
          done

          if [[ "${missing_flags}" == "1" ]];then
            framework_error_message "flags missing"
            return;
          fi

          args=("${@}")
          declare -A final_data=(['type']="${type}")

          for flag in "${!current_flags[@]}";do
            index=0
            for arg in "${args[@]}";do
              if [[ "${arg}" == "--${flag}" ]];then
                flag_name="${args[$index]:2:${#args[$index]}}"
                final_data+=([$flag_name]="$(flag "${flag_name}")")
                break
              else
                index=$((index+1))
              fi
            done
          done

          s_curl_result=$(
            curl  -H "Content-Type: application/json" \
                  -H "Accept: application/json" \
                  -s \
                  --basic --user "${ALWAYSDATA_API_KEY}:" \
                  -X POST \
                  -d "$(generate_json_request_body final_data)" \
                  -i \
                  "${api_url}/database/"
          )

          IFS=$'\n'
          read -rd '' -a curl_result <<<"$s_curl_result"

          IFS=$' '
          read -rd '' -a curl_result_status <<<"${curl_result[0]}"
          IFS=$''

          status_code=${curl_result_status[1]}

          if [[ "${status_code}" == "400" ]];then
            framework_success_message "Alwaysdata API error: La base de données que vous essayez de créer existe déjà"
            return;
          fi

          if [[ "${status_code:0:2}" == "20" ]];then
            framework_success_message "La base de données à bien été créé"
            re_save_databases --force
          else
            framework_error_message "Alwaysdata API error: Une erreur est survenue lors de la création de la base de données"
          fi
        fi
      else
        framework_error_message "Le type saisie n'existe pas !"
      fi
    fi
  }
  eval "$(framework_sub_command -n "database:create" -s "db:c")"

  function database_delete() {
    id=$(flag "id")

    if [[ "${id}" == false ]];then
      framework_error_message "Vous devez renseigner le flag --id !"
      return;
    fi

    s_curl_result=$(
      curl -H "Content-Type: application/json" \
           -H "Accept: application/json" \
           -s \
           -i \
           --basic --user "${ALWAYSDATA_API_KEY}:" \
           -X DELETE \
           "${api_url}/database/${id}/"
    )

    IFS=$'\n'
    read -rd '' -a curl_result <<<"$s_curl_result"

    IFS=$' '
    read -rd '' -a curl_result_status <<<"${curl_result[0]}"
    IFS=$''

    status_code=${curl_result_status[1]}

    if [[ "${status_code}" == "400" ]];then
      framework_error_message "Alwaysdata API error: ${s_curl_result}"

      return;
    fi

    if [[ "${status_code:0:2}" == "20" ]];then
      framework_success_message "La base de données à bien été supprimé"
      re_save_databases --force
    else
      framework_error_message "Alwaysdata API error: Une erreur est survenue lors de la création de la base de données"
    fi
  }
  eval "$(framework_sub_command -n "database:delete" -s "db:d")"

  eval "$(framework_run --with-help)"

    #  get all keys of an object
    #mapfile -t json_object_keys < <(jq -r '.results[0] | keys_unsorted[]' <<<"$json")

    #  get arrays values
    #mapfile -t addresses < <(jq -r '.results[] | .addresses | @csv' <<<"$json")

    #  get not arrays values
    #mapfile -t paths < <(jq -r '.results[] | .path' <<<"$json")
}
