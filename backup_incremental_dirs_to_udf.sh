#!/bin/bash
#
# список директорий для бэкапа:

if [ -z "$1" ]
then
  dir_list="/home/progserega/backup_dirs_to_cdrom.list"
else
  dir_list="`realpath \"$1\"`"
fi

# bdr dvdrw (man mkudffs)
udftype="dvdrw"
if [ ! -z "$2" ]
then
  udftype="$2"
fi

echo "Скрипт может принимать два параметра - список директорий для бэкапа и тип образа (dvdrw/bdr - по-умолчанию bdr). Если параметры не переданы, то используется стандартный путь к файлу директорий для бэкапа и тип диска - bdr."
echo "Выбранный путь: $dir_list"

#growisofs_params="-R -J -joliet-long"
#growisofs_params="-J -joliet-long"
#growisofs_params="-J -udf"
growisofs_params="-no-cache-inodes -udf -full-iso9660-filenames -iso-level 3 -T"
cdrom_dev="/dev/sr0"
files_list="/home/progserega/backup_last_cd_snaphot.files"
exclude_files="/tmp/backup_last_cd_snaphot.exclude_files"
tmp_files_list="/tmp/backup_last_cd_snaphot.files"
work_dir="/mnt/media/tmp/udf"
mount_point="${work_dir}/mount_point"
image_file="udfimage.udf"
udfimage="${work_dir}/${image_file}"

time_stamp="`date +%Y%m%d%H%M.%S`"

if [ ! -f "${udfimage}" ]
then
  echo "Создаём отсутствующий образ $udfimage"
  truncate -s $bdr_size "${udfimage}"
  if [ "dvdrw" == $udftype ]
  then
    truncate -s 4706074624 "${udfimage}"
    mkudffs --media-type=dvdrw "${udfimage}"
  else
    truncate -s 4706074624 "${udfimage}"
    mkudffs --media-type=bdr "${udfimage}"
  fi
fi

if [ ! -d "${mount_point}" ]
then
  echo "Создаём отсутствующую директорию ${mount_point}"
  mkdir -p "${mount_point}"
fi

if [ ! -z "`df|grep \"${mount_point}\"`" ] 
then
  echo "Образ смонтирован - пробуем отмонтировать:"
  sudo umount "${mount_point}"
  if [ ! 0 -eq $? ]
  then
    echo "Ошибка отмонтирования '$mount_point'! Выходим!"
    exit 1
  fi
fi
echo "Монтируем $udfimage в ${mount_point}"
sudo mount -t udf -o loop,rw,user=`whoami` "${udfimage}" "${mount_point}"
if [ ! 0 -eq $? ]
then
  echo "ошибка монтирования образа!"
  echo "команда была: sudo mount -t udf -o loop,rw,user=`whoami` \"${udfimage}\" \"${mount_point}\""
  exit 1
fi
echo "Выставляем права 777 на точку монтирования:"
sudo chmod 777 "${mount_point}"
if [ ! 0 -eq $? ]
then
  echo "ошибка выставления прав на точку монтирования ${mount_point}"
  echo "команда была: chmod 777 \"${mount_point}\""
  exit 1
fi

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
    find_options="-type f -cnewer $stat_file -a -not -name 'backup_last_cd_snaphot.stat' -o -type f -newer $stat_file -a -not -name 'backup_last_cd_snaphot.stat'"
    echo "Формируем список новых файлов, новее отпечатка времени: `stat --printf='%y' \"$stat_file\"` (взято из даты изменения файла '$stat_file')"
    echo "Заметка: Если этот файл удалить, то бэкап будет содержать все файлы из этой директории"
  fi
  #=========== Формируем список на бэкапные файлы:
  # сначала находим файлы исключений:
  find "${dir_to_backup}" -type f -name '.exclude.backup' > $exclude_files
  #echo "команда поиска: 'find \"${dir_to_backup}\" $find_options > $tmp_files_list'"
  find "${dir_to_backup}" $find_options | grep -v 'backup_last_cd_snaphot.stat' > $tmp_files_list
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

size_to_write=$all_summ_files
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
#free_space="`dvd+rw-mediainfo /dev/sr0|grep 'Free Blocks'|tail -n 1|sed 's/.*: *//;s/KB$/048\/1024\/1024/'|bc`"
free_space="`df -k|grep \"${mount_point}\"|awk '{print $4}'|sed 's/$/*1024/'|bc`"
free_summ=$free_space
postfix_free_summ="байт"
if [ 1024 -lt $free_summ ]
then
  free_summ=`expr $free_summ / 1024`
  postfix_free_summ="Кбайт"
fi
if [ 1024 -lt $free_summ ]
then
  free_summ=`expr $free_summ / 1024`
  postfix_free_summ="Мбайт"
fi
if [ 1024 -lt $free_summ ]
then
  free_summ=`expr $free_summ / 1024`
  postfix_free_summ="Гбайт"
fi

echo "На udf-образе свободно: $free_summ $postfix_free_summ."
# берём с запасом в 1 Мб:
size_to_write_zapas=`expr $size_to_write + 1048576`
if [ $size_to_write_zapas -gt $free_space ]
then
  echo "Не достаёт свободного места на образе - пока его записывать и делать новый образ: $size_to_write_zapas > $free_space"
  echo "Отмонтируем образ:"
  sudo umount "${mount_point}"
  echo "Запустите утилиту backup_incremental_write_udf.sh"
  if [ ! 0 -eq $? ]
  then
    echo "сбой отмонтирования '${mount_point}' - выход!"
    exit 1
  fi
  exit 0
fi
echo "Продолжаем? (нажмите любую клавишу)..."

read key

echo "копируем эти файлы в $mount_point для последующей записи образа $udfimage на cd/dvd/bd"

while read file_item
do
  # получаем каталог:
  dir_path="`echo $file_item|sed 's/\(.*\)\/.*$/\1/'`"
  result_dir_path="${mount_point}/${dir_path}"
  mkdir -p "$result_dir_path"
  # копируем файл в этот каталог:
  cp -a "${file_item}" "${result_dir_path}/" 
  if [ ! 0 -eq $? ]
  then
    echo "сбой копирования '${file_item}' в '${result_dir_path}' - выход!"
    exit 1
  fi
done < $files_list

echo "======= `date +%Y.%m.%d-%H:%M:%S` =======" >> "${mount_point}/sessions.list"
cat "${files_list}" >> "${mount_point}/sessions.list"

echo "подсчитываем контрольные суммы"
cur_dir="`pwd`"
cd "${mount_point}"
find . -type f -exec md5sum {} \;|grep -v ' ./md5sum.txt' > /tmp/cdrecord_console.md5
mv /tmp/cdrecord_console.md5 "${mount_point}/md5sum.txt"

echo "Данные скопированы в образ, но образ ещё не отмонтирован из точки монтирования '${mount_point}'"
echo "Вы можете проверить данные в данном образе ('$udfimage'), проверив их в точке монтирования '$mount_point'"
echo "Нажмите любую кнопку для отмонтирования образа и продолжения работы скрипта..."
read key

cd "${cur_dir}"
echo "Отмонтируем образ:"
sudo umount "${mount_point}"
if [ ! 0 -eq $? ]
then
  echo "сбой отмонтирования '${mount_point}' - выход!"
  exit 1
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
