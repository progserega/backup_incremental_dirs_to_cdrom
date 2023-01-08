#!/bin/bash
#
# список директорий для бэкапа:

cdrom_dev="/dev/sr0"
work_dir="/mnt/media/tmp/udf"
mount_point="${work_dir}/mount_point"
image_file="udfimage.udf"
udfimage="${work_dir}/${image_file}"
#write_params="-speed=2"
write_params=""

time_stamp="`date +%Y%m%d%H%M.%S`"

if [ ! -f "${udfimage}" ]
then
  echo "Отсутствует udf-образ для записи: $udfimage"
  echo "Создаёте его и запишите в него необходимые данные с помощью команды: backup_incremental_dirs_to_udf.sh"
  echo "выход"
  exit 1
fi

echo "Размер образа на запись: `ls \"${udfimage}\" -lh|awk '{print $5}'`"
echo "Реальных данных в образе: `ls -sh \"${udfimage}\"|awk '{print $1}'`"

echo "Вы можете проверить данные в данном образе ('$udfimage'), проверив их в точке монтирования '$mount_point'"

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
echo "Нажмите любую кнопку для отмонтирования образа и продолжения работы скрипта..."
read key

echo "Отмонтируем образ:"
sudo umount "${mount_point}"

echo
echo "Всё готово для записи образа на диск. Нажмите любую кнопку для записи образа на диск"
read key
growisofs $write_params -Z -V $time_stamp /dev/sr0=${udfimage}
