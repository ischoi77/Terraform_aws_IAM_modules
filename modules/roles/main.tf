/*
Title: 대규모 infra 구성 및 관리를 위한 AWS IAM 모듈
Author: 최인석(Choi In-seok)
Email: ischoi77@gmail.com, knight7711@naver.com
Created: 2025-07-15
Description: AWS IAM Roles 모듈
repo_url: https://github.com/ischoi77/Terraform_aws_IAM_modules
Version: v1.0.0
*/


locals {
  roles_raw = csvdecode(file(var.roles_csv_file))
  roles = {
    for r in local.roles_raw : r.name => {
      name                 = r.name
      description          = try(r.description, null)
      assume_file          = r.assume_policy_file
      policy_names         = r.policies == "" ? [] : split(",", r.policies)
      path                 = try(r.path, var.default_path)
      max_session_duration = try(tonumber(r.max_session_duration), null)
      tags = (
        r.tags == "" ? {} :
        {
          for pair in split(";", r.tags) :
          trimspace(split("=", pair)[0]) => trimspace(split("=", pair)[1])
        }
      )
    }
  }


  # AWS managed + service-linked managed ARN 통합
  combined_managed_policy_arns = merge(
    var.managed_policy_arns,
    {
      for name in var.managed_service_role_policy_names :
      name => lookup(var.managed_service_role_policy_arns, name, null)
      if contains(keys(var.managed_service_role_policy_arns), name)
    }
  )
  
  all_policy_arns = merge(
  local.combined_managed_policy_arns,
  var.custom_policy_arns
)

  role_policy_attachments_flat = flatten([
    for role_key, role in local.roles : [
      for policy_name in role.policy_names : {
        key        = "${role_key}::${policy_name}"
        role_name  = role.name
        policy_arn = lookup(local.all_policy_arns, trimspace(policy_name), null)
      }
    ]
  ])

  role_policy_attachments = {
    for r in local.role_policy_attachments_flat :
    r.key => r
  }
  
  assume_policy_paths = {
    for role_name, role in local.roles :
    role_name => "${path.root}/assume_role_policy_files/${trimspace(role.assume_file)}.json"
  }

  # 파일 존재 여부 확인
  roles_with_policy_file = {
    for role_name, role in local.roles :
    role_name => merge(role, {
      assume_policy_path = local.assume_policy_paths[role_name]
    })
    if fileexists(local.assume_policy_paths[role_name])
  }
}


resource "aws_iam_role" "this" {
  for_each = local.roles_with_policy_file

  name                 = each.value.name
  description          = each.value.description
  assume_role_policy   = file(each.value.assume_policy_path)
  path                 = each.value.path
  max_session_duration = each.value.max_session_duration

  tags = merge(var.common_tags,
     try(each.value.tags, {}),
    {
      "Name" = each.value.name
    }
  )

  lifecycle {
    ignore_changes = [ description ]
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = {
    for k, v in local.role_policy_attachments :
    k => v if contains(keys(aws_iam_role.this), v.role_name)
  }

  role       = aws_iam_role.this[each.value.role_name].name
  policy_arn = each.value.policy_arn
}