/*
Title: 대규모 infra 구성 및 관리를 위한 AWS IAM 모듈
Author: 최인석(Choi In-seok)
Email: ischoi77@gmail.com, knight7711@naver.com
Created: 2025-07-15
Description: AWS IAM Policies 모듈
repo_url: https://github.com/ischoi77/Terraform_aws_IAM_modules
Version: v1.0.0
*/

locals {
  # 모든 정책 파일 목록
  policy_files = fileset(var.policies.policy_dir, "*.json")

  all_policy_map = {
    for file in local.policy_files :
    trimsuffix(file, ".json") => {
      name   = trimsuffix(file, ".json")
      path   = "${var.policies.policy_dir}/${file}"
      policy = file("${var.policies.policy_dir}/${file}")
    }
  }

  # 중복된 정책 이름 여부 (true이면 중복됨)
  is_conflicted_policy_name = {
    for name in keys(local.all_policy_map) :
    name => contains(var.policies.managed_policy_names, name) || contains(var.policies.managed_service_role_policy_names, name)
  }

  # 중복되지 않은 사용자 정의 정책만 필터링
  custom_policy_map = {
    for name, v in local.all_policy_map :
    name => v if local.is_conflicted_policy_name[name] == false
  }

  # 중복되어 제외된 이름 목록
  skipped_policy_names = [
    for name, skip in local.is_conflicted_policy_name : name if skip
  ]

  managed_policy_arns = {
    for name in var.policies.managed_policy_names :
    name => "arn:aws:iam::aws:policy/${name}"
  }

  managed_service_role_policy_arns = {
    for name in var.policies.managed_service_role_policy_names :
    name => "arn:aws:iam::aws:policy/aws-service-role/${name}"
  }
}


resource "aws_iam_policy" "this" {
  for_each = local.custom_policy_map

  name   = each.value.name
  policy = each.value.policy
  description = each.value.name

  lifecycle {
    ignore_changes = [ description, tags ]
  }
}
