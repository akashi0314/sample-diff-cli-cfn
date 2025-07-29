import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface VpcEc2StackProps extends cdk.StackProps {
  projectTag?: string;
  environmentTag?: string;
  vpcCidr?: string;
  privateSubnetCidr?: string;
  availabilityZone?: string;
  instanceType?: ec2.InstanceType;
}

export class VpcEc2Stack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: VpcEc2StackProps) {
    super(scope, id, props);

    // デフォルト値の設定
    const projectTag = props?.projectTag || 'demo';
    const environmentTag = props?.environmentTag || 'development';
    const vpcCidr = props?.vpcCidr || '10.0.0.0/16';
    const privateSubnetCidr = props?.privateSubnetCidr || '10.0.1.0/24';
    const availabilityZone = props?.availabilityZone || 'us-east-1a';
    const instanceType = props?.instanceType || ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO);

    // 共通タグ
    const commonTags = {
      Project: projectTag,
      Environment: environmentTag,
      CreatedBy: 'CDK'
    };

    // VPC作成
    const vpc = new ec2.Vpc(this, 'VPC', {
      ipAddresses: ec2.IpAddresses.cidr(vpcCidr),
      maxAzs: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // タグを追加
    cdk.Tags.of(vpc).add('Name', `${projectTag}-vpc`);
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(vpc).add(key, value);
    });

    // プライベートサブネット取得
    const privateSubnet = vpc.isolatedSubnets[0];

    // VPCエンドポイント用セキュリティグループ
    const vpcEndpointSg = new ec2.SecurityGroup(this, 'VPCEndpointSecurityGroup', {
      vpc,
      description: 'Security group for VPC endpoints',
      allowAllOutbound: false,
    });

    // EC2インスタンス用セキュリティグループ
    const instanceSg = new ec2.SecurityGroup(this, 'InstanceSecurityGroup', {
      vpc,
      description: 'Security group for demo EC2 instance',
      allowAllOutbound: false,
    });

    // セキュリティグループルール設定
    vpcEndpointSg.addIngressRule(
      instanceSg,
      ec2.Port.tcp(443),
      'HTTPS from EC2 instances'
    );

    instanceSg.addEgressRule(
      vpcEndpointSg,
      ec2.Port.tcp(443),
      'HTTPS to VPC endpoints'
    );

    // セキュリティグループにタグ追加
    cdk.Tags.of(vpcEndpointSg).add('Name', `${projectTag}-vpc-endpoint-sg`);
    cdk.Tags.of(instanceSg).add('Name', `${projectTag}-instance-sg`);
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(vpcEndpointSg).add(key, value);
      cdk.Tags.of(instanceSg).add(key, value);
    });

    // VPCエンドポイント作成
    const ssmEndpoint = new ec2.InterfaceVpcEndpoint(this, 'SSMVPCEndpoint', {
      vpc,
      service: ec2.InterfaceVpcEndpointAwsService.SSM,
      subnets: { subnets: [privateSubnet] },
      securityGroups: [vpcEndpointSg],
    });

    // SSMエンドポイントにポリシーを追加
    ssmEndpoint.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.AnyPrincipal()],
        actions: [
          'ssm:UpdateInstanceInformation',
          'ssm:SendCommand',
          'ssm:ListCommandInvocations',
          'ssm:DescribeInstanceInformation',
          'ssm:GetDeployablePatchSnapshotForInstance',
          'ssm:GetDefaultPatchBaseline',
          'ssm:GetManifest',
          'ssm:GetParameter',
          'ssm:GetParameters',
          'ssm:ListAssociations',
          'ssm:ListInstanceAssociations',
          'ssm:PutInventory',
          'ssm:PutComplianceItems',
          'ssm:PutConfigurePackageResult',
          'ssm:UpdateAssociationStatus',
          'ssm:UpdateInstanceAssociationStatus'
        ],
        resources: ['*']
      })
    );

    const ssmMessagesEndpoint = new ec2.InterfaceVpcEndpoint(this, 'SSMMessagesVPCEndpoint', {
      vpc,
      service: ec2.InterfaceVpcEndpointAwsService.SSM_MESSAGES,
      subnets: { subnets: [privateSubnet] },
      securityGroups: [vpcEndpointSg],
    });

    const ec2MessagesEndpoint = new ec2.InterfaceVpcEndpoint(this, 'EC2MessagesVPCEndpoint', {
      vpc,
      service: ec2.InterfaceVpcEndpointAwsService.EC2_MESSAGES,
      subnets: { subnets: [privateSubnet] },
      securityGroups: [vpcEndpointSg],
    });

    // IAMロール作成
    const ec2Role = new iam.Role(this, 'EC2Role', {
      roleName: `${projectTag}-ec2-ssm-role-${this.region}`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
      ]
    });

    // IAMロールにタグ追加
    cdk.Tags.of(ec2Role).add('Name', `${projectTag}-ec2-role`);
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(ec2Role).add(key, value);
    });

    // UserDataスクリプト
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      'yum update -y',
      'yum install -y amazon-ssm-agent',
      'systemctl enable amazon-ssm-agent',
      'systemctl start amazon-ssm-agent',
      '',
      '# SSM Agentの状態確認',
      'systemctl status amazon-ssm-agent',
      '',
      '# ログにインスタンス情報を記録',
      `echo "$(date): Instance ${this.stackName} started successfully" >> /var/log/cloudformation-init.log`,
      `echo "Project: ${projectTag}" >> /var/log/cloudformation-init.log`,
      `echo "Environment: ${environmentTag}" >> /var/log/cloudformation-init.log`
    );

    // EC2インスタンス作成
    const instance = new ec2.Instance(this, 'Instance', {
      vpc,
      instanceType,
      machineImage: ec2.MachineImage.latestAmazonLinux({
        generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
      }),
      vpcSubnets: { subnets: [privateSubnet] },
      securityGroup: instanceSg,
      role: ec2Role,
      userData,
    });

    // インスタンスにタグ追加
    cdk.Tags.of(instance).add('Name', `${projectTag}-instance`);
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(instance).add(key, value);
    });

    // Outputs
    new cdk.CfnOutput(this, 'VpcId', {
      description: 'VPC ID',
      value: vpc.vpcId,
      exportName: `${this.stackName}-VpcId`
    });

    new cdk.CfnOutput(this, 'PrivateSubnetId', {
      description: 'プライベートサブネット ID',
      value: privateSubnet.subnetId,
      exportName: `${this.stackName}-PrivateSubnetId`
    });

    new cdk.CfnOutput(this, 'InstanceId', {
      description: 'EC2インスタンス ID',
      value: instance.instanceId,
      exportName: `${this.stackName}-InstanceId`
    });

    new cdk.CfnOutput(this, 'InstanceSecurityGroupId', {
      description: 'EC2インスタンスのセキュリティグループ ID',
      value: instanceSg.securityGroupId,
      exportName: `${this.stackName}-InstanceSecurityGroupId`
    });

    new cdk.CfnOutput(this, 'VPCEndpointSecurityGroupId', {
      description: 'VPCエンドポイントのセキュリティグループ ID',
      value: vpcEndpointSg.securityGroupId,
      exportName: `${this.stackName}-VPCEndpointSecurityGroupId`
    });

    new cdk.CfnOutput(this, 'SSMVPCEndpointId', {
      description: 'SSM VPCエンドポイント ID',
      value: ssmEndpoint.vpcEndpointId,
      exportName: `${this.stackName}-SSMVPCEndpointId`
    });

    new cdk.CfnOutput(this, 'SSMMessagesVPCEndpointId', {
      description: 'SSM Messages VPCエンドポイント ID',
      value: ssmMessagesEndpoint.vpcEndpointId,
      exportName: `${this.stackName}-SSMMessagesVPCEndpointId`
    });

    new cdk.CfnOutput(this, 'EC2MessagesVPCEndpointId', {
      description: 'EC2 Messages VPCエンドポイント ID',
      value: ec2MessagesEndpoint.vpcEndpointId,
      exportName: `${this.stackName}-EC2MessagesVPCEndpointId`
    });

    new cdk.CfnOutput(this, 'IAMRoleArn', {
      description: 'EC2用IAMロールのARN',
      value: ec2Role.roleArn,
      exportName: `${this.stackName}-IAMRoleArn`
    });

    new cdk.CfnOutput(this, 'SSMSessionManagerCommand', {
      description: 'Systems Manager Session Managerでの接続コマンド',
      value: `aws ssm start-session --target ${instance.instanceId}`
    });

    new cdk.CfnOutput(this, 'ProjectTag', {
      description: 'プロジェクト名',
      value: projectTag,
      exportName: `${this.stackName}-ProjectTag`
    });

    new cdk.CfnOutput(this, 'EnvironmentTag', {
      description: '環境名',
      value: environmentTag,
      exportName: `${this.stackName}-EnvironmentTag`
    });
  }
}