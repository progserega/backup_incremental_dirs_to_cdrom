#!/bin/bash
#
# список директорий для бэкапа:

if [ -z "$1" ]
then
  dir_list="/home/progserega/backup_dirs_to_cdrom.list"
else
  dir_list="$1"
fi

echo "Скрипт может принимать один параметр - список директорий для бэкапа. Если параметр не передан, то используется стандартный путь к файлу."
echo "Выбранный путь: $dir_list"

growisofs_params="-R -J -joliet-long"
#growisofs_params="-J -joliet-long"
cdrom_dev="/dev/sr0"
cache_dir="/mnt/media/tmp/cd_console_burn_cache"
files_list="/home/progserega/backup_last_cd_snaphot.files"
exclude_files="/tmp/backup_last_cd_snaphot.exclude_files"
tmp_files_list="/tmp/backup_last_cd_snaphot.files"

time_stamp="`date +%Y%m%d%H%M.%S`"
rm -rf /mnt/media/tmp/cd_console_burn_cache/*
cat /dev/null > $files_list

echo "Беру список директорий для бэкапа из файла: $dir_list"

all_summ_files=0

while read dir_to_backup
do
  echo "Ищу новые файлы в ${dir_to_backup}..."
  stat_file="${dir_to_backup}/backup_last_cd_snaphot.stat"
  if [ ! -f "$stat_file" ]
  then
    echo "отстутствует стат-файл прошлой сессии ($stat_file) - бэкаплю все файлы"
    find_options="-type f -a -not -name 'backup_last_cd_snaphot.stat'"
  else
    # cnewer - новее по полю changed (изменён) в stat, newer - по полю modufy (модифицирован):
    # Пример:
    # скачали файл с интернета в архиве (книжку), распаковали и получаем, что modify (изменено содержимое файла) было в лохматом году (когда паковали этот файл в архив в интернете),
    # а changed - время, когда распаковал сам только что из архива. 
    # если же изменить содержимое файла - то поменяется и modify.
    # чтобы отслеживать и то и другое время - используется обе опции (-cnewer и -newer):
    find_options="-type f -cnewer \"$stat_file\" -a -not -name 'backup_last_cd_snaphot.stat' -o -type f -newer \"$stat_file\" -a -not -name 'backup_last_cd_snaphot.stat'"
    echo "Формируем список новых файлов, новее отпечатка времени: `stat --printf='%y' \"$stat_file\"` (взято из даты изменения файла '$stat_file')"
    echo "Заметка: Если этот файл удалить, то бэкап будет содержать все файлы из этой директории"
  fi
  #=========== Формируем список на бэкапные файлы:
  # сначала находим файлы исключений:
  find "${dir_to_backup}" -type f -name '.exclude.backup' > $exclude_files
  find "${dir_to_backup}" $find_options > $tmp_files_list
  # исключаем директории, содержащие файл .exclude.backup:
  all_num_files=`cat $tmp_files_list|wc -l`
  while read exclude_file_path
  do
    echo "Нашли файл исключения директории: '$exclude_file_path'"
    exclude_dir_path="`echo $exclude_file_path|sed 's/\(.*\)\/.*$/\1/'`"
    echo "пропускаем все дочерние объекты в '$exclude_dir_path'"
    cat $tmp_files_list|egrep -v "^${exclude_dir_path}.*$" > "${tmp_files_list}.tmp"
    mv "${tmp_files_list}.tmp" "${tmp_files_list}"
  done < $exclude_files
  # добавляем готовый список файлов (за исключением директорий и их дочерних объектов 
  # в которых был файл .exclude.backup):
  skipped_num_files=`cat $tmp_files_list|wc -l`
  if [ ! $all_num_files -eq $skipped_num_files ]
  then
     echo "найдено файлов: $all_num_files, пропущено файлов: `expr $all_num_files - $skipped_num_files`, всего добавлено файлов: $skipped_num_files"
  else
     echo "найдено файлов: $all_num_files - все добавлены в бэкап"
  fi

  echo
  echo "Список первых пяти файлов на бэкап для '$dir_to_backup':"
  head -n 5 $tmp_files_list
  echo

	echo "считаем размер файлов в директории '$dir_to_backup' для бэкапа..."
	summ_size=0
	while read file_item
	do
	  # получаем каталог:
	  file_size="`stat --printf='%s' \"${file_item}\"`"
	  summ_size=`expr $summ_size + $file_size`
	done < $tmp_files_list
	# прибавляем к общему размеру:
	all_summ_files=`expr $all_summ_files + $summ_size`
	postfix="байт"
	if [ 1024 -lt $summ_size ]
	then
	  summ_size=`expr $summ_size / 1024`
	  postfix="Кбайт"
	fi
	if [ 1024 -lt $summ_size ]
	then
	  summ_size=`expr $summ_size / 1024`
	  postfix="Мбайт"
	fi
	if [ 1024 -lt $summ_size ]
	then
	  summ_size=`expr $summ_size / 1024`
	  postfix="Гбайт"
	fi
	echo "Размер всех файлов на запись для директории '$dir_to_backup': $summ_size $postfix"

  cat "${tmp_files_list}" >> $files_list
done < "${dir_list}"

#==============================================

#========== Формируем кэш из файлов, для создания iso ========
num_files=`cat $files_list|wc -l`
echo
echo "Всего во всех директориях собрано $num_files файлов для копирования (список в файле: $files_list)"
if [ 0 -eq $num_files ]
then
  echo "Нет файлов для архивирования на cdrom. Выход."
  exit 0
fi

echo
echo "Список первых пяти файлов общего списка на бэкап (всех директорий):"
head -n 5 $files_list
echo

echo "считаем размер данных для бэкапа..."
postfix_all_summ_files="байт"
if [ 1024 -lt $all_summ_files ]
then
  all_summ_files=`expr $all_summ_files / 1024`
  postfix_all_summ_files="Кбайт"
fi
if [ 1024 -lt $all_summ_files ]
then
  all_summ_files=`expr $all_summ_files / 1024`
  postfix_all_summ_files="Мбайт"
fi
if [ 1024 -lt $all_summ_files ]
then
  all_summ_files=`expr $all_summ_files / 1024`
  postfix_all_summ_files="Гбайт"
fi
echo "Размер всех файлов на запись: $all_summ_files $postfix_all_summ_files"
echo "определяем свободное место на диске:"
free_space="`dvd+rw-mediainfo /dev/sr0|grep 'Free Blocks'|tail -n 1|sed 's/.*: *//;s/KB$/048\/1024\/1024/'|bc`"
echo "На cd/dvd/bd диске свободно: $free_space Мб."
echo "Продолжаем? (нажмите любую клавишу)..."

read key

echo "копируем эти файлы в $cache_dir для последующей записи на cd/dvd/bd"

while read file_item
do
  # получаем каталог:
  dir_path="`echo $file_item|sed 's/\(.*\)\/.*$/\1/'`"
  result_dir_path="${cache_dir}/${dir_path}"
  mkdir -p "$result_dir_path"
  # копируем файл в этот каталог:
  cp -a "${file_item}" "${result_dir_path}/" 
done < $files_list

echo "подсчитываем контрольные суммы"
cd "${cache_dir}"
find . -type f -exec md5sum {} \; > /tmp/cdrecord_console.md5
mv /tmp/cdrecord_console.md5 "${cache_dir}/${time_stamp}.md5"

# запись:
echo "проверяем наличие мультисессии:"
multi_status="`dvd+rw-mediainfo $cdrom_dev|grep 'Disc status:'|sed 's/.*: *//'`"

if [ "$multi_status" == "blank" ]
then
  echo "нет мультисессии. Чистый диск. Начинаем новую сессию..."
  session_param="-Z"
  echo "формируем MULTISESSION.readme в корне диска для инструкции как монтировать многосессионный диск"
  echo "For mount multisession disc - use command: mount -o session=1,ro /dev/sr0 /mnt/cdrom
Для монтирования мультисессионного диска (а он предполагается, что такой) - нужно использовать команду:
mount -o session=1,ro /dev/sr0 /mnt/cdrom
При этом нужно учесть, что по документации 1 - это номер сессии. А на практике получается, что это некий флаг вида:
1 - показывать данные всех сессий
любое другое число - показывать только самую первую сессию.

В случае, если эта опция указана, а диск не имеет сессий - то в логах будут ошибки, но диск примонтируется корректно." > "${cache_dir}/MULTISESSION.readme"
else
  if [ "$multi_status" == "appendable" ]
  then
     echo "Нашли мультисессию. Продолжаем существующую сессию..."
     session_param="-M"
  else
    echo "Неизвестный статус диска: '$multi_status' (ожидался либо 'blank', либо 'appendable' в строчке 'Disc status:' в выводе команды:  'dvd+rw-mediainfo $cdrom_dev' - выход"
    exit 1
  fi
fi

echo "пробуем в режиме тестирования (-dry-run - без записи):"
growisofs -dry-run $session_param $cdrom_dev $growisofs_params -volid $time_stamp $cache_dir
if [ ! 0 -eq $? ]
then
  echo "Ошибка выполнения команды тестирования:"
  echo "growisofs -dry-run $session_param $cdrom_dev $growisofs_params -volid $time_stamp $cache_dir"
  echo "Может быть на диске нет свободного места для записи $all_summ_files $postfix_all_summ_files?"
  exit 1
else
  echo "успешно прошли тестирование записи данных на диск. Приступаем к реальной записи:"
fi
echo "ждём 10 секунд - ещё можно всё отменить..."
sleep 10

growisofs $session_param $cdrom_dev $growisofs_params -volid $time_stamp $cache_dir
if [ ! 0 -eq $? ]
then
  echo "Ошибка выполнения команды записи:"
  echo "growisofs $session_param $cdrom_dev $growisofs_params -volid $time_stamp $cache_dir"
  exit 1
else
  echo "успешно записали данные на диск"
fi

echo
echo "Т.к. Вы можете хотеть продублировать этот набор копируемых файлов на иные болванки, то
Вам предоставляется выбор - обновлять или нет отметку времени бэкапа.
В случае, если обновить её, то повторный запуск скрипта - соберёт для бэкапа только файлы, дата изменения
которых новее, чем отметка времени бэкапа данной директории (для каждой директории свой файл отметки).
Если же метку не обновлять, то повторный запуск скрипта - соберёт для бэкапа те же файлы, что и этот запуск - 
это может быть удобно в случае, если Вы хотите сделать ещё одну копию этого бэкапа, но на другие болванки.

Итак, обновляем статус бэкапа? Если обновляем - нажмите любую клавишу.
Если не хотите обновлять статус - нажмите 'n'..."
read key
if [ "n" == "$key" ]
then
  echo "Вышли без обновления статусов бэкапов"
  exit 0
fi

# в каждой директории для бэкапа отдельно создаём файл-отметку статуса:
while read dir_to_backup
do
  stat_file="${dir_to_backup}/backup_last_cd_snaphot.stat"
  echo "обновляем статус бэкапа посредством времени модификации статусного файла (при последующем запуске будут записываться данные новее этого отпечатка): $stat_file"
  echo $time_stamp > "$stat_file"
  touch -t $time_stamp "$stat_file"
done < "${dir_list}"

echo "Успешное завершение скрипта"
exit 0
