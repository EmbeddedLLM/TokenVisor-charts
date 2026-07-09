#!/bin/bash

# Delete deployments
kubectl delete -f emu-deployment.yaml -n tokenvisor
kubectl delete -f studio-deployment.yaml -n tokenvisor
kubectl delete -f cnpg-cluster-deploy.yaml -n tokenvisor

# Apply deployments
kubectl apply -f cnpg-cluster-deploy.yaml -n tokenvisor
kubectl apply -f emu-deployment.yaml -n tokenvisor
kubectl apply -f studio-deployment.yaml -n tokenvisor
