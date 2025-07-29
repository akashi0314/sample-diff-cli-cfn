#!/bin/bash
# AWS CLI直接実行スクリプト
# CloudFormationテンプレートと同等のリソースをCLIで作成する教育用コンテンツ
# IaCとCLI直接実行の違いを学習するためのデモスクリプト
set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 設定ファイルを読み込み
if [[ -f "$SCRIPT_DIR/config.env" ]]; then
    source "$SCRIPT_DIR/config.env"
else
    echo "❌ エラー: config.env が見つかりません"
    exit 1
fi

# 色付きログ関数（ログファイル書き込みを無効化）
log_info() {
    local message="$1"
    echo -e "\033[32m[INFO]\033[0m $message" >&2
}

log_warn() {
    local message="$1"
    echo -e "\033[33m[WARN]\033[0m $message" >&2
}

log_error() {
    local message="$1"
    echo -e "\033[31m[ERROR]\033[0m $message" >&2
}

# 使用方法の表示
usage() {
    echo "使用方法: $0 [オプション]"
    echo ""
    echo "オプション:"
    echo "  -p, --profile PROFILE         AWS CLIプロファイル"
    echo "  -r, --region REGION           AWSリージョン (デフォルト: $AWS_REGION)"
    echo "  -d, --delete                  作成したリソースの削除"
    echo "  -h, --help                    このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0                                    # リソース作成"
    echo "  $0 --delete                           # リソース削除"
    echo "  $0 --profile production --region ap-northeast-1"
}

# デフォルト値設定
OPERATION="create"
RESOURCE_PREFIX="${PROJECT_TAG:-demo}-cli"

# CLI作成時のリソース識別子を格納するファイル
RESOURCE_IDS_FILE="$SCRIPT_DIR/cli-resource-ids.json"

# コマンドライン引数の解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--profile)
            AWS_PROFILE="$2"
            log_info "AWS CLIプロファイルを設定: $AWS_PROFILE"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -d|--delete)
            OPERATION="delete"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "不明なオプション: $1"
            usage
            exit 1
            ;;
    esac
done

# AWS CLI認証方法の判定と設定
setup_aws_cli_options() {
    # 一時クレデンシャルの確認
    if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
        log_info "一時クレデンシャル（セッショントークン）を検出"
        # 一時クレデンシャル使用時は環境変数を優先し、プロファイルは使用しない
        unset AWS_PROFILE
        export AWS_DEFAULT_REGION="$AWS_REGION"
        log_info "認証方法: 一時クレデンシャル（環境変数）"
        return 0
    fi
    
    # プロファイルが明示的に設定されている場合
    if [[ -n "${AWS_PROFILE:-}" ]]; then
        log_info "AWS CLIプロファイル: $AWS_PROFILE"
        export AWS_PROFILE
        export AWS_DEFAULT_REGION="$AWS_REGION"
        log_info "認証方法: プロファイル ($AWS_PROFILE)"
        return 0
    fi
    
    # デフォルト認証情報を使用
    unset AWS_PROFILE
    export AWS_DEFAULT_REGION="$AWS_REGION"
    log_info "AWS CLIプロファイル: 未設定（デフォルト認証情報使用）"
    log_info "認証方法: デフォルト認証情報"
}

# 必要なツールの確認
check_requirements() {
    log_info "必要なツールを確認中..."
    
    # AWS CLI確認
    if ! command -v aws &> /dev/null; then
        log_error "❌ AWS CLIがインストールされていません"
        log_error "インストール方法: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    local aws_version
    aws_version=$(aws --version 2>&1)
    log_info "✅ AWS CLI: $aws_version"
    
    # jq確認
    if ! command -v jq &> /dev/null; then
        log_error "❌ jqがインストールされていません（このスクリプトでは必須）"
        log_error "このスクリプトを実行する前に、jqをインストールしてください"
        log_error "インストール方法:"
        log_error "  Ubuntu/Debian: sudo apt-get install jq"
        log_error "  CentOS/RHEL: sudo yum install jq"
        log_error "  Amazon Linux: sudo yum install jq"
        log_error "  macOS: brew install jq"
        exit 1
    fi
    local jq_version
    jq_version=$(jq --version 2>&1)
    log_info "✅ jq: $jq_version"
    
    log_info "ツール確認完了"
}

# AWS認証の確認
check_aws_auth() {
    log_info "AWS認証確認開始"
    
    # 認証情報の確認
    log_info "aws sts get-caller-identity --region $AWS_REGION を実行中..."
    
    local caller_identity
    if caller_identity=$(aws sts get-caller-identity --region "$AWS_REGION" 2>&1); then
        log_info "✅ AWS認証成功"
        echo "$caller_identity" | jq -r '"ユーザーID: " + .UserId + "\nアカウント: " + .Account + "\nARN: " + .Arn' || echo "$caller_identity"
    else
        log_error "❌ AWS認証失敗"
        log_error "エラー詳細: $caller_identity"
        log_error ""
        log_error "トラブルシューティング:"
        log_error "1. AWS認証情報が正しく設定されているか確認してください"
        log_error "2. 一時クレデンシャルの場合、有効期限が切れていないか確認してください"
        log_error "3. AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN環境変数を確認してください"
        log_error "4. ~/.aws/credentials と ~/.aws/config ファイルを確認してください"
        exit 1
    fi
}

# リソースIDを保存する関数
save_resource_id() {
    local resource_type="$1"
    local resource_id="$2"
    local resource_name="$3"
    
    # JSONファイルが存在しない場合は初期化
    if [[ ! -f "$RESOURCE_IDS_FILE" ]]; then
        echo "{}" > "$RESOURCE_IDS_FILE"
    fi
    
    # リソース情報を追加
    local temp_file=$(mktemp)
    jq --arg type "$resource_type" --arg id "$resource_id" --arg name "$resource_name" \
        '.[$type] = {"id": $id, "name": $name}' \
        "$RESOURCE_IDS_FILE" > "$temp_file"
    mv "$temp_file" "$RESOURCE_IDS_FILE"
    
    log_info "リソースID保存: $resource_type = $resource_id ($resource_name)"
}

# リソースIDを取得する関数
get_resource_id() {
    local resource_type="$1"
    
    if [[ ! -f "$RESOURCE_IDS_FILE" ]]; then
        echo ""
        return
    fi
    
    jq -r --arg type "$resource_type" '.[$type].id // empty' "$RESOURCE_IDS_FILE"
}

# 最新のAMI IDを取得
get_latest_ami_id() {
    log_info "最新のAmazon Linux AMI IDを取得中..."
    
    local ami_id=""
    
    # まずAmazon Linux 2023を試行
    log_info "Amazon Linux 2023 AMI IDを検索中..."
    ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=al2023-ami-*-x86_64" \
            "Name=state,Values=available" \
            "Name=architecture,Values=x86_64" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    # Amazon Linux 2023が見つかった場合
    if [[ -n "$ami_id" && "$ami_id" != "None" && "$ami_id" != "null" ]]; then
        log_info "Amazon Linux 2023 AMI ID: $ami_id"
        echo "$ami_id"
        return 0
    fi
    
    # フォールバック: Amazon Linux 2を試行
    log_warn "Amazon Linux 2023が見つかりません。Amazon Linux 2を検索中..."
    ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
            "Name=state,Values=available" \
            "Name=architecture,Values=x86_64" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    # Amazon Linux 2が見つかった場合
    if [[ -n "$ami_id" && "$ami_id" != "None" && "$ami_id" != "null" ]]; then
        log_info "Amazon Linux 2 AMI ID: $ami_id"
        echo "$ami_id"
        return 0
    fi
    
    # 最後のフォールバック: より汎用的な検索
    log_warn "Amazon Linux 2も見つかりません。より汎用的な検索を実行中..."
    ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=*amazon*linux*" \
            "Name=state,Values=available" \
            "Name=architecture,Values=x86_64" \
            "Name=virtualization-type,Values=hvm" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [[ -n "$ami_id" && "$ami_id" != "None" && "$ami_id" != "null" ]]; then
        log_warn "汎用検索で見つかったAMI ID: $ami_id"
        echo "$ami_id"
        return 0
    fi
    
    # 全ての検索が失敗した場合の詳細エラー
    log_error "AMI IDの取得に失敗しました"
    log_error "デバッグ情報:"
    log_error "  リージョン: $AWS_REGION"
    log_error "  検索試行: Amazon Linux 2023 → Amazon Linux 2 → 汎用検索"
    
    # 利用可能なAMIの一覧を表示（デバッグ用）
    log_error "利用可能なAmazon所有のAMI（最新5件）:"
    aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=state,Values=available" \
            "Name=architecture,Values=x86_64" \
            "Name=virtualization-type,Values=hvm" \
        --query 'Images | sort_by(@, &CreationDate) | [-5:] | [].[ImageId, Name]' \
        --output table \
        --region "$AWS_REGION" 2>/dev/null || log_error "AMI一覧の取得も失敗しました"
    
    return 1
}

# リソースの存在確認関数
check_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case $resource_type in
        "vpc")
            aws ec2 describe-vpcs \
                --filters "Name=tag:Name,Values=$resource_name" "Name=state,Values=available" \
                --query 'Vpcs[0].VpcId' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null | grep -v "None" || true
            ;;
        "subnet")
            aws ec2 describe-subnets \
                --filters "Name=tag:Name,Values=$resource_name" "Name=state,Values=available" \
                --query 'Subnets[0].SubnetId' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null | grep -v "None" || true
            ;;
        "security-group")
            aws ec2 describe-security-groups \
                --filters "Name=group-name,Values=$resource_name" \
                --query 'SecurityGroups[0].GroupId' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null | grep -v "None" || true
            ;;
        "iam-role")
            aws iam get-role \
                --role-name "$resource_name" \
                --query 'Role.RoleName' \
                --output text 2>/dev/null || true
            ;;
        "instance-profile")
            aws iam get-instance-profile \
                --instance-profile-name "$resource_name" \
                --query 'InstanceProfile.InstanceProfileName' \
                --output text 2>/dev/null || true
            ;;
        "vpc-endpoint")
            aws ec2 describe-vpc-endpoints \
                --filters "Name=tag:Name,Values=$resource_name" "Name=state,Values=available" \
                --query 'VpcEndpoints[0].VpcEndpointId' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null | grep -v "None" || true
            ;;
        "ec2-instance")
            aws ec2 describe-instances \
                --filters "Name=tag:Name,Values=$resource_name" "Name=instance-state-name,Values=running,pending" \
                --query 'Reservations[0].Instances[0].InstanceId' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null | grep -v "None" || true
            ;;
    esac
}

# VPCの作成（冪等性対応）
create_vpc() {
    log_info "1. VPCを作成中..."
    
    local vpc_name="${RESOURCE_PREFIX}-vpc"
    local existing_vpc_id
    existing_vpc_id=$(check_resource_exists "vpc" "$vpc_name")
    
    if [[ -n "$existing_vpc_id" ]]; then
        log_info "既存のVPCが見つかりました: $existing_vpc_id"
        save_resource_id "vpc" "$existing_vpc_id" "$vpc_name"
        return 0
    fi
    
    local vpc_id
    vpc_id=$(aws ec2 create-vpc \
        --cidr-block "${VPC_CIDR:-10.0.0.0/16}" \
        --query 'Vpc.VpcId' \
        --output text \
        --region "$AWS_REGION")
    
    if [[ -n "$vpc_id" ]]; then
        log_info "VPC作成完了: $vpc_id"
        save_resource_id "vpc" "$vpc_id" "$vpc_name"
        
        # VPCの設定
        aws ec2 modify-vpc-attribute \
            --vpc-id "$vpc_id" \
            --enable-dns-hostnames \
            --region "$AWS_REGION"
        
        aws ec2 modify-vpc-attribute \
            --vpc-id "$vpc_id" \
            --enable-dns-support \
            --region "$AWS_REGION"
        
        # タグ付け
        aws ec2 create-tags \
            --resources "$vpc_id" \
            --tags \
                "Key=Name,Value=$vpc_name" \
                "Key=Project,Value=${PROJECT_TAG:-demo}" \
                "Key=Environment,Value=${ENVIRONMENT_TAG:-Demo}" \
                "Key=CreatedBy,Value=AWS-CLI" \
            --region "$AWS_REGION"
    else
        log_error "VPCの作成に失敗しました"
        exit 1
    fi
}

# プライベートサブネットの作成（冪等性対応）
create_private_subnet() {
    local vpc_id="$1"
    log_info "2. プライベートサブネットを作成中..."
    
    local subnet_name="${RESOURCE_PREFIX}-private-subnet"
    local existing_subnet_id
    existing_subnet_id=$(check_resource_exists "subnet" "$subnet_name")
    
    if [[ -n "$existing_subnet_id" ]]; then
        log_info "既存のプライベートサブネットが見つかりました: $existing_subnet_id"
        save_resource_id "private_subnet" "$existing_subnet_id" "$subnet_name"
        return 0
    fi
    
    local subnet_id
    subnet_id=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "${PRIVATE_SUBNET_CIDR:-${SUBNET_CIDR:-10.0.1.0/24}}" \
        --availability-zone "${AVAILABILITY_ZONE:-${AWS_AVAILABILITY_ZONE:-us-east-1a}}" \
        --query 'Subnet.SubnetId' \
        --output text \
        --region "$AWS_REGION")
    
    if [[ -n "$subnet_id" ]]; then
        log_info "プライベートサブネット作成完了: $subnet_id"
        save_resource_id "private_subnet" "$subnet_id" "$subnet_name"
        
        # タグ付け
        aws ec2 create-tags \
            --resources "$subnet_id" \
            --tags \
                "Key=Name,Value=$subnet_name" \
                "Key=Project,Value=${PROJECT_TAG:-demo}" \
                "Key=Environment,Value=${ENVIRONMENT_TAG:-development}" \
                "Key=CreatedBy,Value=AWS-CLI" \
            --region "$AWS_REGION"
    else
        log_error "プライベートサブネットの作成に失敗しました"
        exit 1
    fi
}

# セキュリティグループの作成（冪等性対応）
create_security_groups() {
    local vpc_id="$1"
    log_info "3. セキュリティグループを作成中..."
    
    # インスタンス用セキュリティグループ
    log_info "3-1. インスタンス用セキュリティグループを作成中..."
    local instance_sg_name="${RESOURCE_PREFIX}-instance-sg"
    local existing_instance_sg_id
    existing_instance_sg_id=$(check_resource_exists "security-group" "$instance_sg_name")
    
    local instance_sg_id
    if [[ -n "$existing_instance_sg_id" ]]; then
        log_info "既存のインスタンス用セキュリティグループが見つかりました: $existing_instance_sg_id"
        instance_sg_id="$existing_instance_sg_id"
        save_resource_id "instance_sg" "$instance_sg_id" "$instance_sg_name"
    else
        instance_sg_id=$(aws ec2 create-security-group \
            --group-name "$instance_sg_name" \
            --description "Security group for demo EC2 instance" \
            --vpc-id "$vpc_id" \
            --query 'GroupId' \
            --output text \
            --region "$AWS_REGION")
        
        save_resource_id "instance_sg" "$instance_sg_id" "$instance_sg_name"
        log_info "インスタンス用セキュリティグループ作成完了: $instance_sg_id"
    fi
    
    # VPCエンドポイント用セキュリティグループ
    log_info "3-2. VPCエンドポイント用セキュリティグループを作成中..."
    local vpc_endpoint_sg_name="${RESOURCE_PREFIX}-vpc-endpoint-sg"
    local existing_vpc_endpoint_sg_id
    existing_vpc_endpoint_sg_id=$(check_resource_exists "security-group" "$vpc_endpoint_sg_name")
    
    local vpc_endpoint_sg_id
    if [[ -n "$existing_vpc_endpoint_sg_id" ]]; then
        log_info "既存のVPCエンドポイント用セキュリティグループが見つかりました: $existing_vpc_endpoint_sg_id"
        vpc_endpoint_sg_id="$existing_vpc_endpoint_sg_id"
        save_resource_id "vpc_endpoint_sg" "$vpc_endpoint_sg_id" "$vpc_endpoint_sg_name"
    else
        vpc_endpoint_sg_id=$(aws ec2 create-security-group \
            --group-name "$vpc_endpoint_sg_name" \
            --description "Security group for VPC endpoints" \
            --vpc-id "$vpc_id" \
            --query 'GroupId' \
            --output text \
            --region "$AWS_REGION")
        
        save_resource_id "vpc_endpoint_sg" "$vpc_endpoint_sg_id" "$vpc_endpoint_sg_name"
        log_info "VPCエンドポイント用セキュリティグループ作成完了: $vpc_endpoint_sg_id"
    fi
    
    # セキュリティグループルールの設定（冪等性対応）
    log_info "3-3. セキュリティグループルールを設定中..."
    
    # 既存ルールの確認と追加（エラーを無視して冪等性を保つ）
    aws ec2 authorize-security-group-egress \
        --group-id "$instance_sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr "${VPC_CIDR:-10.0.0.0/16}" \
        --region "$AWS_REGION" 2>/dev/null || log_info "アウトバウンドルールは既に存在しています"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$vpc_endpoint_sg_id" \
        --protocol tcp \
        --port 443 \
        --source-group "$instance_sg_id" \
        --region "$AWS_REGION" 2>/dev/null || log_info "インバウンドルールは既に存在しています"
    
    # タグ付け（既存の場合はエラーを無視）
    aws ec2 create-tags \
        --resources "$instance_sg_id" "$vpc_endpoint_sg_id" \
        --tags \
            "Key=Project,Value=${PROJECT_TAG:-demo}" \
            "Key=Environment,Value=${ENVIRONMENT_TAG:-development}" \
            "Key=CreatedBy,Value=AWS-CLI" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    aws ec2 create-tags \
        --resources "$instance_sg_id" \
        --tags "Key=Name,Value=$instance_sg_name" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    aws ec2 create-tags \
        --resources "$vpc_endpoint_sg_id" \
        --tags "Key=Name,Value=$vpc_endpoint_sg_name" \
        --region "$AWS_REGION" 2>/dev/null || true
}

# IAMロールとインスタンスプロファイルの作成（冪等性対応）
create_iam_resources() {
    log_info "4. IAMロールとインスタンスプロファイルを作成中..."
    
    local role_name="${RESOURCE_PREFIX}-ec2-ssm-role-${AWS_REGION}"
    local instance_profile_name="${RESOURCE_PREFIX}-ec2-instance-profile-${AWS_REGION}"
    
    # 既存IAMロールの確認
    local existing_role
    existing_role=$(check_resource_exists "iam-role" "$role_name")
    
    if [[ -n "$existing_role" ]]; then
        log_info "既存のIAMロールが見つかりました: $role_name"
        save_resource_id "iam_role" "$role_name" "$role_name"
    else
        # 信頼ポリシーの作成
        local trust_policy=$(cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
        
        # IAMロールの作成
        log_info "4-1. IAMロールを作成中..."
        local role_arn
        role_arn=$(aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "$trust_policy" \
            --tags \
                "Key=Name,Value=${RESOURCE_PREFIX}-ec2-role" \
                "Key=Project,Value=${PROJECT_TAG:-demo}" \
                "Key=Environment,Value=${ENVIRONMENT_TAG:-development}" \
                "Key=CreatedBy,Value=AWS-CLI" \
            --query 'Role.Arn' \
            --output text 2>/dev/null)
        
        if [[ -n "$role_arn" ]]; then
            log_info "IAMロール作成完了: $role_arn"
            save_resource_id "iam_role" "$role_name" "$role_name"
        else
            log_error "IAMロールの作成に失敗しました"
            exit 1
        fi
    fi
    
    # マネージドポリシーのアタッチ（冪等性対応）
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || log_info "ポリシーは既にアタッチされています"
    
    # 既存インスタンスプロファイルの確認
    local existing_instance_profile
    existing_instance_profile=$(check_resource_exists "instance-profile" "$instance_profile_name")
    
    if [[ -n "$existing_instance_profile" ]]; then
        log_info "既存のインスタンスプロファイルが見つかりました: $instance_profile_name"
        save_resource_id "instance_profile" "$instance_profile_name" "$instance_profile_name"
    else
        # インスタンスプロファイルの作成
        log_info "4-2. インスタンスプロファイルを作成中..."
        aws iam create-instance-profile \
            --instance-profile-name "$instance_profile_name"
        
        save_resource_id "instance_profile" "$instance_profile_name" "$instance_profile_name"
        log_info "インスタンスプロファイル作成完了: $instance_profile_name"
    fi
    
    # ロールをインスタンスプロファイルに追加（冪等性対応）
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$instance_profile_name" \
        --role-name "$role_name" 2>/dev/null || log_info "ロールは既にインスタンスプロファイルに関連付けられています"
    
    log_info "IAMリソース作成完了"
}

# VPCエンドポイントの作成（冪等性対応）
create_vpc_endpoints() {
    local vpc_id="$1"
    local subnet_id="$2"
    local vpc_endpoint_sg_id="$3"
    
    log_info "5. VPCエンドポイントを作成中..."
    
    # 各エンドポイントのサービス名と種類
    local endpoints=(
        "ssm:com.amazonaws.${AWS_REGION}.ssm:ssm_endpoint"
        "ssm-messages:com.amazonaws.${AWS_REGION}.ssmmessages:ssm_messages_endpoint"
        "ec2-messages:com.amazonaws.${AWS_REGION}.ec2messages:ec2_messages_endpoint"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r endpoint_name service_name resource_key <<< "$endpoint_info"
        
        log_info "5-${endpoint_name}. ${endpoint_name} VPCエンドポイントを作成中..."
        
        # 既存エンドポイントの確認（より詳細なチェック）
        local existing_endpoint_id
        existing_endpoint_id=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=service-name,Values=$service_name" "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available,pending" \
            --query 'VpcEndpoints[0].VpcEndpointId' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null | grep -v "None" || true)
        
        if [[ -n "$existing_endpoint_id" ]]; then
            log_info "既存の${endpoint_name}エンドポイントが見つかりました: $existing_endpoint_id"
            save_resource_id "$resource_key" "$existing_endpoint_id" "${endpoint_name}-endpoint"
        else
            local endpoint_id
            if [[ "$endpoint_name" == "ssm" ]]; then
                endpoint_id=$(aws ec2 create-vpc-endpoint \
                    --vpc-id "$vpc_id" \
                    --service-name "$service_name" \
                    --vpc-endpoint-type Interface \
                    --subnet-ids "$subnet_id" \
                    --security-group-ids "$vpc_endpoint_sg_id" \
                    --no-private-dns-enabled \
                    --policy-document '{
                        "Version": "2012-10-17",
                        "Statement": [
                            {
                                "Effect": "Allow",
                                "Principal": "*",
                                "Action": [
                                    "ssm:UpdateInstanceInformation",
                                    "ssm:SendCommand",
                                    "ssm:ListCommandInvocations",
                                    "ssm:DescribeInstanceInformation",
                                    "ssm:GetDeployablePatchSnapshotForInstance",
                                    "ssm:GetDefaultPatchBaseline",
                                    "ssm:GetManifest",
                                    "ssm:GetParameter",
                                    "ssm:GetParameters",
                                    "ssm:ListAssociations",
                                    "ssm:ListInstanceAssociations",
                                    "ssm:PutInventory",
                                    "ssm:PutComplianceItems",
                                    "ssm:PutConfigurePackageResult",
                                    "ssm:UpdateAssociationStatus",
                                    "ssm:UpdateInstanceAssociationStatus"
                                ],
                                "Resource": "*"
                            }
                        ]
                    }' \
                    --query 'VpcEndpoint.VpcEndpointId' \
                    --output text \
                    --region "$AWS_REGION")
            else
                endpoint_id=$(aws ec2 create-vpc-endpoint \
                    --vpc-id "$vpc_id" \
                    --service-name "$service_name" \
                    --vpc-endpoint-type Interface \
                    --subnet-ids "$subnet_id" \
                    --security-group-ids "$vpc_endpoint_sg_id" \
                    --no-private-dns-enabled \
                    --query 'VpcEndpoint.VpcEndpointId' \
                    --output text \
                    --region "$AWS_REGION")
            fi
            
            save_resource_id "$resource_key" "$endpoint_id" "${endpoint_name}-endpoint"
            log_info "${endpoint_name}エンドポイント作成完了: $endpoint_id"
            
            # エンドポイントにタグを追加
            aws ec2 create-tags \
                --resources "$endpoint_id" \
                --tags \
                    "Key=Name,Value=${RESOURCE_PREFIX}-${endpoint_name}-endpoint" \
                    "Key=Project,Value=${PROJECT_TAG:-demo}" \
                    "Key=Environment,Value=${ENVIRONMENT_TAG:-development}" \
                    "Key=CreatedBy,Value=AWS-CLI" \
                --region "$AWS_REGION" 2>/dev/null || log_warn "エンドポイントへのタグ付けに失敗しました"
        fi
    done
    
    log_info "VPCエンドポイント作成完了"
    log_warn "注意: プライベートDNSは無効化されています。SSM接続時はエンドポイントのDNS名を使用する必要があります。"
}

# EC2インスタンスの作成（冪等性対応）
create_ec2_instance() {
    local subnet_id="$1"
    local instance_sg_id="$2"
    local instance_profile_name="$3"
    
    log_info "6. EC2インスタンスを作成中..."
    
    local instance_name="${RESOURCE_PREFIX}-instance"
    local existing_instance_id
    existing_instance_id=$(check_resource_exists "ec2-instance" "$instance_name")
    
    if [[ -n "$existing_instance_id" ]]; then
        log_info "既存のEC2インスタンスが見つかりました: $existing_instance_id"
        save_resource_id "ec2_instance" "$existing_instance_id" "$instance_name"
        return 0
    fi
    
    # 最新のAMI IDを取得
    local ami_id
    ami_id=$(get_latest_ami_id)
    
    # UserDataスクリプトの作成
    local user_data=$(cat << 'EOF'
#!/bin/bash
yum update -y
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
# SSM Agentの状態確認
systemctl status amazon-ssm-agent
# ログにインスタンス情報を記録
echo "$(date): Instance started successfully" >> /var/log/cloudformation-init.log
echo "Project: demo" >> /var/log/cloudformation-init.log
echo "Environment: development" >> /var/log/cloudformation-init.log
EOF
)
    
    # EC2インスタンスの起動
    local instance_id
    instance_id=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --count 1 \
        --instance-type "${INSTANCE_TYPE:-t3.micro}" \
        --subnet-id "$subnet_id" \
        --security-group-ids "$instance_sg_id" \
        --iam-instance-profile Name="$instance_profile_name" \
        --user-data "$user_data" \
        --tag-specifications \
            "ResourceType=instance,Tags=[
                {Key=Name,Value=$instance_name},
                {Key=Project,Value=${PROJECT_TAG:-demo}},
                {Key=Environment,Value=${ENVIRONMENT_TAG:-development}},
                {Key=CreatedBy,Value=AWS-CLI}
            ]" \
        --query 'Instances[0].InstanceId' \
        --output text \
        --region "$AWS_REGION")
    
    if [[ -n "$instance_id" ]]; then
        log_info "EC2インスタンス作成完了: $instance_id"
        save_resource_id "ec2_instance" "$instance_id" "$instance_name"
        
        # インスタンスの起動を待機
        log_info "インスタンスの起動を待機中..."
        aws ec2 wait instance-running \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION"
        
        log_info "インスタンスが起動しました"
    else
        log_error "EC2インスタンスの作成に失敗しました"
        exit 1
    fi
}

# リソースの作成
create_resources() {
    log_info "=== AWS CLI による直接リソース作成を開始 ==="
    
    # VPCの作成
    create_vpc
    local vpc_id=$(get_resource_id "vpc")
    if [[ -z "$vpc_id" ]]; then
        log_error "VPC IDの取得に失敗しました"
        exit 1
    fi
    
    # プライベートサブネットの作成
    create_private_subnet "$vpc_id"
    local subnet_id=$(get_resource_id "private_subnet")
    if [[ -z "$subnet_id" ]]; then
        log_error "サブネット IDの取得に失敗しました"
        exit 1
    fi
    
    # セキュリティグループの作成
    create_security_groups "$vpc_id"
    local instance_sg_id=$(get_resource_id "instance_sg")
    local vpc_endpoint_sg_id=$(get_resource_id "vpc_endpoint_sg")
    if [[ -z "$instance_sg_id" || -z "$vpc_endpoint_sg_id" ]]; then
        log_error "セキュリティグループ IDの取得に失敗しました"
        exit 1
    fi
    
    # IAMリソースの作成
    create_iam_resources
    local instance_profile_name=$(get_resource_id "instance_profile")
    if [[ -z "$instance_profile_name" ]]; then
        log_error "インスタンスプロファイル名の取得に失敗しました"
        exit 1
    fi
    
    # IAMリソースの伝播を待機
    log_info "IAMリソースの伝播を待機中..."
    sleep 30
    
    # VPCエンドポイントの作成
    create_vpc_endpoints "$vpc_id" "$subnet_id" "$vpc_endpoint_sg_id"
    
    # VPCエンドポイントの準備完了を待機
    log_info "VPCエンドポイントの準備完了を待機中..."
    sleep 60
    
    # EC2インスタンスの作成
    create_ec2_instance "$subnet_id" "$instance_sg_id" "$instance_profile_name"
    local instance_id=$(get_resource_id "ec2_instance")
    if [[ -z "$instance_id" ]]; then
        log_error "EC2インスタンス IDの取得に失敗しました"
        exit 1
    fi
    
    # 構築結果の表示
    show_creation_result "$instance_id"
}

# リソースの削除
delete_resources() {
    log_info "=== 作成したリソースを削除中 ==="
    
    if [[ ! -f "$RESOURCE_IDS_FILE" ]]; then
        log_warn "リソースIDファイルが見つかりません: $RESOURCE_IDS_FILE"
        exit 1
    fi
    
    # EC2インスタンスの削除
    local instance_id
    instance_id=$(get_resource_id "ec2_instance")
    if [[ -n "$instance_id" ]]; then
        log_info "1. EC2インスタンスを削除中: $instance_id"
        aws ec2 terminate-instances \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION"
        
        log_info "インスタンスの終了を待機中..."
        aws ec2 wait instance-terminated \
            --instance-ids "$instance_id" \
            --region "$AWS_REGION"
    fi
    
    # VPCエンドポイントの削除
    for endpoint_type in "ssm_endpoint" "ssm_messages_endpoint" "ec2_messages_endpoint"; do
        local endpoint_id
        endpoint_id=$(get_resource_id "$endpoint_type")
        if [[ -n "$endpoint_id" ]]; then
            log_info "2. VPCエンドポイントを削除中: $endpoint_id"
            aws ec2 delete-vpc-endpoints \
                --vpc-endpoint-ids "$endpoint_id" \
                --region "$AWS_REGION"
        fi
    done
    
    # IAMリソースの削除
    local role_name
    role_name=$(get_resource_id "iam_role")
    local instance_profile_name
    instance_profile_name=$(get_resource_id "instance_profile")
    
    if [[ -n "$instance_profile_name" && -n "$role_name" ]]; then
        log_info "3. IAMリソースを削除中..."
        
        # インスタンスプロファイルからロールを削除
        aws iam remove-role-from-instance-profile \
            --instance-profile-name "$instance_profile_name" \
            --role-name "$role_name" 2>/dev/null || true
        
        # インスタンスプロファイルの削除
        aws iam delete-instance-profile \
            --instance-profile-name "$instance_profile_name" 2>/dev/null || true
        
        # ロールからポリシーをデタッチ
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true
        
        # ロールの削除
        aws iam delete-role \
            --role-name "$role_name" 2>/dev/null || true
    fi
    
    # セキュリティグループの削除
    for sg_type in "instance_sg" "vpc_endpoint_sg"; do
        local sg_id
        sg_id=$(get_resource_id "$sg_type")
        if [[ -n "$sg_id" ]]; then
            log_info "4. セキュリティグループを削除中: $sg_id"
            aws ec2 delete-security-group \
                --group-id "$sg_id" \
                --region "$AWS_REGION" 2>/dev/null || true
        fi
    done
    
    # サブネットの削除
    local subnet_id
    subnet_id=$(get_resource_id "private_subnet")
    if [[ -n "$subnet_id" ]]; then
        log_info "5. サブネットを削除中: $subnet_id"
        aws ec2 delete-subnet \
            --subnet-id "$subnet_id" \
            --region "$AWS_REGION" 2>/dev/null || true
    fi
    
    # VPCの削除
    local vpc_id
    vpc_id=$(get_resource_id "vpc")
    if [[ -n "$vpc_id" ]]; then
        log_info "6. VPCを削除中: $vpc_id"
        aws ec2 delete-vpc \
            --vpc-id "$vpc_id" \
            --region "$AWS_REGION" 2>/dev/null || true
    fi
    
    # リソースIDファイルの削除
    if [[ -f "$RESOURCE_IDS_FILE" ]]; then
        rm -f "$RESOURCE_IDS_FILE"
        log_info "リソースIDファイルを削除しました"
    fi
    
    log_info "=== リソース削除完了 ==="
}

# 構築結果の表示
show_creation_result() {
    local instance_id="$1"
    
    log_info "=== AWS CLI による構築結果 ==="
    log_info "構築日時: $(date)"
    log_info "リージョン: $AWS_REGION"
    log_info "EC2インスタンス ID: $instance_id"
    log_info ""
    log_info "Systems Manager Session Managerでの接続方法:"
    echo "  aws ssm start-session --target $instance_id --region $AWS_REGION"
    log_info ""
    
    # 作成されたリソースの詳細表示
    log_info "作成されたリソース一覧:"
    if [[ -f "$RESOURCE_IDS_FILE" ]]; then
        jq -r 'to_entries[] | "  \(.key): \(.value.id) (\(.value.name))"' "$RESOURCE_IDS_FILE"
    fi
    
    # 構築結果を保存
    cat > cli-creation-info.txt << EOF
=== AWS CLI による構築結果 ===
構築日時: $(date)
リージョン: $AWS_REGION
EC2インスタンス ID: $instance_id
SSM Session Manager接続コマンド:
aws ssm start-session --target $instance_id --region $AWS_REGION
作成されたリソース詳細:
$(jq -r 'to_entries[] | "  \(.key): \(.value.id) (\(.value.name))"' "$RESOURCE_IDS_FILE" 2>/dev/null || echo "  リソース情報の取得に失敗")
注意: このスクリプトで作成したリソースは個別に削除する必要があります
CloudFormationと異なり、一括削除機能はありません
EOF
    log_info "構築情報は cli-creation-info.txt に保存されました"
}

# メイン処理
main() {
    log_info "=== AWS CLI 直接実行による環境構築 ==="
    log_info "操作: $OPERATION"
    log_info "リージョン: $AWS_REGION"
    log_info "リソースプレフィックス: $RESOURCE_PREFIX"
    log_info ""
    log_info "📚 教育ポイント: このスクリプトはCloudFormationテンプレートと同等の"
    log_info "   リソースをAWS CLIで直接作成する方法を学習するためのものです"
    log_info ""
    
    # AWS CLI認証設定
    setup_aws_cli_options
    
    # 事前チェック
    check_requirements
    check_aws_auth
    
    case $OPERATION in
        "create")
            create_resources
            ;;
        "delete")
            delete_resources
            ;;
        *)
            log_error "不明な操作: $OPERATION"
            usage
            exit 1
            ;;
    esac
    
    log_info "=== 操作完了 ==="
}

# エラーハンドリング
handle_error() {
    local exit_code=$?
    local line_number=$1
    local command="$BASH_COMMAND"
    
    log_error "🚨 スクリプトエラー発生"
    log_error "📍 ライン番号: $line_number"
    log_error "💥 実行コマンド: $command"
    log_error "📊 終了コード: $exit_code"
    
    # スタック情報の表示
    log_error "📚 コールスタック:"
    local i=1
    while [[ $i -lt ${#BASH_LINENO[@]} ]]; do
        log_error "  [$i] ${BASH_SOURCE[$i+1]}:${BASH_LINENO[$i]} in ${FUNCNAME[$i+1]}"
        ((i++))
    done
    
    log_error "🔧 トラブルシューティング:"
    log_error "  1. AWS認証情報を確認: aws sts get-caller-identity"
    log_error "  2. 権限を確認: IAMポリシーに必要な権限があるか"
    log_error "  3. 作成途中のリソースがAWSコンソールに残っている可能性があります"
    
    exit $exit_code
}

# エラートラップの設定
trap 'handle_error $LINENO' ERR

# スクリプト実行
main "$@"