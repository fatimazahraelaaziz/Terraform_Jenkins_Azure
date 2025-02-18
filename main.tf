terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}


# Variables utilisées dans la configuration
variable "resource_group_name" {
  default = "Terraform-RG"
}

variable "location" {
  default = "francecentral" # 🇫🇷 Région Azure en France (Paris)
}

variable "admin_username" {
  default = "azureuser"
}

variable "subscription_id" {
  description = "L'ID de votre abonnement Azure"
  type        = string
}

variable "client_id" {
  description = "L'ID du client (Application ID) pour l'authentification"
  type        = string
}

variable "client_secret" {
  description = "Le secret du client pour l'authentification"
  type        = string
}

variable "tenant_id" {
  description = "L'ID de votre locataire Azure"
  type        = string
}


provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}


# Création du groupe de ressources
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Création du réseau virtuel 
resource "azurerm_virtual_network" "vnet" {
  name                = "Terraform-VNet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"] # Plage d'adresses du réseau
}

# Création des sous-réseaux 
resource "azurerm_subnet" "subnet1" {
  name                 = "Subnet-01"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}



resource "azurerm_subnet" "subnet2" {
  name                 = "Subnet-02"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.2.0/24"]
}

# Création du groupe de sécurité réseau 
resource "azurerm_network_security_group" "nsg" {
  name                = "Terraform-NSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Ajout d'une règle pour autoriser SSH (port 22)
resource "azurerm_network_security_rule" "allow_ssh" {
  name                        = "Allow-SSH"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

# Création des interfaces réseau (NIC) pour chaque machine virtuelle
resource "azurerm_network_interface" "nic" {
  for_each = toset(["jenkins-master", "jenkins-slave", "ansible"])

  name                = "NIC-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Dynamic"
  }
}


# Création des machines virtuelles sous Ubuntu 18.04
resource "azurerm_linux_virtual_machine" "vm" {
  for_each = toset(["jenkins-master", "jenkins-slave", "ansible"])

  name                = each.key
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s" # 
  admin_username      = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic[each.key].id]

  # Ajout de la clé SSH pour connexion sécurisée
  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub") 
  }

  # Configuration du disque OS
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Sélection de l’image Ubuntu
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}
