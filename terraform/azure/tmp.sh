AVAILABLE_VM=$(az vm list-skus --location swedencentral --query "[?resourceType=='virtualMachines' && !restrictions[0]].name" -o tsv | grep -i "Standard" | head -n 1)

if [ -n "$AVAILABLE_VM" ]; then
  echo "Znaleziono dostępny rozmiar: $AVAILABLE_VM. Podmieniam i buduję..."
  sed -i "s/Standard_DS1_v2/$AVAILABLE_VM/g" instance.tf
else
  echo "Azure zablokowało wszystkie maszyny dla tego konta w Szwecji. Wyłączam ten moduł..."
  mv instance.tf instance.tf.disabled
fi

terraform apply