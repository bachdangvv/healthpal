using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace HealthPal.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "AspNetRoles",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    normalized_name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    concurrency_stamp = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_roles", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUsers",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    user_name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    normalized_user_name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    email = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    normalized_email = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    email_confirmed = table.Column<bool>(type: "boolean", nullable: false),
                    password_hash = table.Column<string>(type: "text", nullable: true),
                    security_stamp = table.Column<string>(type: "text", nullable: true),
                    concurrency_stamp = table.Column<string>(type: "text", nullable: true),
                    phone_number = table.Column<string>(type: "text", nullable: true),
                    phone_number_confirmed = table.Column<bool>(type: "boolean", nullable: false),
                    two_factor_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    lockout_end = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    lockout_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    access_failed_count = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_users", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "AspNetRoleClaims",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    role_id = table.Column<string>(type: "text", nullable: false),
                    claim_type = table.Column<string>(type: "text", nullable: true),
                    claim_value = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_role_claims", x => x.id);
                    table.ForeignKey(
                        name: "fk_asp_net_role_claims_asp_net_roles_role_id",
                        column: x => x.role_id,
                        principalTable: "AspNetRoles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserClaims",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    claim_type = table.Column<string>(type: "text", nullable: true),
                    claim_value = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_user_claims", x => x.id);
                    table.ForeignKey(
                        name: "fk_asp_net_user_claims_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserLogins",
                columns: table => new
                {
                    login_provider = table.Column<string>(type: "text", nullable: false),
                    provider_key = table.Column<string>(type: "text", nullable: false),
                    provider_display_name = table.Column<string>(type: "text", nullable: true),
                    user_id = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_user_logins", x => new { x.login_provider, x.provider_key });
                    table.ForeignKey(
                        name: "fk_asp_net_user_logins_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserRoles",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "text", nullable: false),
                    role_id = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_user_roles", x => new { x.user_id, x.role_id });
                    table.ForeignKey(
                        name: "fk_asp_net_user_roles_asp_net_roles_role_id",
                        column: x => x.role_id,
                        principalTable: "AspNetRoles",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_asp_net_user_roles_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AspNetUserTokens",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "text", nullable: false),
                    login_provider = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    value = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asp_net_user_tokens", x => new { x.user_id, x.login_provider, x.name });
                    table.ForeignKey(
                        name: "fk_asp_net_user_tokens_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "daily_health_summaries",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    local_date = table.Column<DateOnly>(type: "date", nullable: false),
                    timezone = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    sleep_minutes = table.Column<int>(type: "integer", nullable: true),
                    steps = table.Column<int>(type: "integer", nullable: true),
                    average_heart_rate = table.Column<double>(type: "double precision", nullable: true),
                    min_heart_rate = table.Column<double>(type: "double precision", nullable: true),
                    max_heart_rate = table.Column<double>(type: "double precision", nullable: true),
                    resting_heart_rate = table.Column<double>(type: "double precision", nullable: true),
                    active_calories = table.Column<double>(type: "double precision", nullable: true),
                    exercise_count = table.Column<int>(type: "integer", nullable: false),
                    exercise_duration_minutes = table.Column<int>(type: "integer", nullable: false),
                    coverage_flags = table.Column<string>(type: "jsonb", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_daily_health_summaries", x => x.id);
                    table.CheckConstraint("ck_daily_health_summaries_active_calories", "active_calories IS NULL OR active_calories >= 0");
                    table.CheckConstraint("ck_daily_health_summaries_exercise_count", "exercise_count >= 0");
                    table.CheckConstraint("ck_daily_health_summaries_exercise_duration", "exercise_duration_minutes >= 0");
                    table.CheckConstraint("ck_daily_health_summaries_sleep", "sleep_minutes IS NULL OR sleep_minutes >= 0");
                    table.CheckConstraint("ck_daily_health_summaries_steps", "steps IS NULL OR steps >= 0");
                    table.ForeignKey(
                        name: "fk_daily_health_summaries_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "devices",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "text", nullable: false),
                    id = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    platform = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    app_version = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    model_version = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    source_preference = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    last_seen_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_devices", x => new { x.user_id, x.id });
                    table.ForeignKey(
                        name: "fk_devices_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "exercise_sessions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    external_record_id = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    type = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    start_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    end_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    zone_offset_minutes = table.Column<int>(type: "integer", nullable: false),
                    duration_minutes = table.Column<int>(type: "integer", nullable: false),
                    calories = table.Column<double>(type: "double precision", nullable: true),
                    source_id = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_exercise_sessions", x => x.id);
                    table.CheckConstraint("ck_exercise_sessions_calories", "calories IS NULL OR calories >= 0");
                    table.CheckConstraint("ck_exercise_sessions_duration", "duration_minutes >= 0");
                    table.CheckConstraint("ck_exercise_sessions_range", "end_utc >= start_utc");
                    table.ForeignKey(
                        name: "fk_exercise_sessions_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "fatigue_assessments",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    evaluated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    local_date = table.Column<DateOnly>(type: "date", nullable: false),
                    model_version = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    base_probability = table.Column<double>(type: "double precision", nullable: true),
                    calibrated_probability = table.Column<double>(type: "double precision", nullable: true),
                    threshold = table.Column<double>(type: "double precision", nullable: false),
                    status = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    coverage_hours = table.Column<int>(type: "integer", nullable: false),
                    latest_sample_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    data_freshness_minutes = table.Column<int>(type: "integer", nullable: true),
                    missing_reasons = table.Column<string>(type: "jsonb", nullable: false),
                    feature_vector_hash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    feature_vector_json = table.Column<string>(type: "text", nullable: true),
                    created_by = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_fatigue_assessments", x => x.id);
                    table.CheckConstraint("ck_fatigue_assessments_base_probability", "base_probability IS NULL OR (base_probability >= 0 AND base_probability <= 1)");
                    table.CheckConstraint("ck_fatigue_assessments_calibrated_probability", "calibrated_probability IS NULL OR (calibrated_probability >= 0 AND calibrated_probability <= 1)");
                    table.CheckConstraint("ck_fatigue_assessments_coverage_hours", "coverage_hours >= 0");
                    table.CheckConstraint("ck_fatigue_assessments_freshness", "data_freshness_minutes IS NULL OR data_freshness_minutes >= 0");
                    table.CheckConstraint("ck_fatigue_assessments_threshold", "threshold >= 0 AND threshold <= 1");
                    table.ForeignKey(
                        name: "fk_fatigue_assessments_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "hourly_health_bins",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    hour_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    zone_offset_minutes = table.Column<int>(type: "integer", nullable: false),
                    hr_mean = table.Column<double>(type: "double precision", nullable: true),
                    hr_min = table.Column<double>(type: "double precision", nullable: true),
                    hr_max = table.Column<double>(type: "double precision", nullable: true),
                    hr_sample_count = table.Column<int>(type: "integer", nullable: false),
                    steps = table.Column<int>(type: "integer", nullable: true),
                    active_calories = table.Column<double>(type: "double precision", nullable: true),
                    source_id = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_hourly_health_bins", x => x.id);
                    table.CheckConstraint("ck_hourly_health_bins_active_calories", "active_calories IS NULL OR active_calories >= 0");
                    table.CheckConstraint("ck_hourly_health_bins_hr_sample_count", "hr_sample_count >= 0");
                    table.CheckConstraint("ck_hourly_health_bins_steps", "steps IS NULL OR steps >= 0");
                    table.ForeignKey(
                        name: "fk_hourly_health_bins_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "refresh_tokens",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    token_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    device_id = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    family_id = table.Column<Guid>(type: "uuid", nullable: false),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    revoked_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    replaced_by_token_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_refresh_tokens", x => x.id);
                    table.ForeignKey(
                        name: "fk_refresh_tokens_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "sync_batches",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    device_id = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    idempotency_key = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    schema_version = table.Column<int>(type: "integer", nullable: false),
                    generated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    payload_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    result_json = table.Column<string>(type: "jsonb", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_sync_batches", x => x.id);
                    table.ForeignKey(
                        name: "fk_sync_batches_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_profiles",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "text", nullable: false),
                    display_name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    birth_date = table.Column<DateOnly>(type: "date", nullable: true),
                    gender = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                    height_cm = table.Column<double>(type: "double precision", nullable: true),
                    weight_kg = table.Column<double>(type: "double precision", nullable: true),
                    goal = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    daily_step_goal = table.Column<int>(type: "integer", nullable: false),
                    timezone = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    preferred_source_id = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    experimental_fatigue_consent = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_profiles", x => x.user_id);
                    table.CheckConstraint("ck_user_profiles_daily_step_goal", "daily_step_goal >= 100");
                    table.CheckConstraint("ck_user_profiles_height", "height_cm IS NULL OR (height_cm >= 50 AND height_cm <= 250)");
                    table.CheckConstraint("ck_user_profiles_weight", "weight_kg IS NULL OR (weight_kg >= 20 AND weight_kg <= 400)");
                    table.ForeignKey(
                        name: "fk_user_profiles_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_asp_net_role_claims_role_id",
                table: "AspNetRoleClaims",
                column: "role_id");

            migrationBuilder.CreateIndex(
                name: "RoleNameIndex",
                table: "AspNetRoles",
                column: "normalized_name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_asp_net_user_claims_user_id",
                table: "AspNetUserClaims",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_asp_net_user_logins_user_id",
                table: "AspNetUserLogins",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_asp_net_user_roles_role_id",
                table: "AspNetUserRoles",
                column: "role_id");

            migrationBuilder.CreateIndex(
                name: "EmailIndex",
                table: "AspNetUsers",
                column: "normalized_email");

            migrationBuilder.CreateIndex(
                name: "UserNameIndex",
                table: "AspNetUsers",
                column: "normalized_user_name",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_daily_health_summaries_user_id_local_date",
                table: "daily_health_summaries",
                columns: new[] { "user_id", "local_date" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_exercise_sessions_user_id_external_record_id",
                table: "exercise_sessions",
                columns: new[] { "user_id", "external_record_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_exercise_sessions_user_id_start_utc",
                table: "exercise_sessions",
                columns: new[] { "user_id", "start_utc" });

            migrationBuilder.CreateIndex(
                name: "ix_fatigue_assessments_user_id_evaluated_at_utc_model_version",
                table: "fatigue_assessments",
                columns: new[] { "user_id", "evaluated_at_utc", "model_version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_fatigue_assessments_user_id_local_date_evaluated_at_utc",
                table: "fatigue_assessments",
                columns: new[] { "user_id", "local_date", "evaluated_at_utc" });

            migrationBuilder.CreateIndex(
                name: "ix_hourly_health_bins_user_id_hour_utc",
                table: "hourly_health_bins",
                columns: new[] { "user_id", "hour_utc" });

            migrationBuilder.CreateIndex(
                name: "ix_hourly_health_bins_user_id_hour_utc_source_id",
                table: "hourly_health_bins",
                columns: new[] { "user_id", "hour_utc", "source_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_token_hash",
                table: "refresh_tokens",
                column: "token_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_user_id_family_id",
                table: "refresh_tokens",
                columns: new[] { "user_id", "family_id" });

            migrationBuilder.CreateIndex(
                name: "ix_sync_batches_user_id_device_id_idempotency_key",
                table: "sync_batches",
                columns: new[] { "user_id", "device_id", "idempotency_key" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AspNetRoleClaims");

            migrationBuilder.DropTable(
                name: "AspNetUserClaims");

            migrationBuilder.DropTable(
                name: "AspNetUserLogins");

            migrationBuilder.DropTable(
                name: "AspNetUserRoles");

            migrationBuilder.DropTable(
                name: "AspNetUserTokens");

            migrationBuilder.DropTable(
                name: "daily_health_summaries");

            migrationBuilder.DropTable(
                name: "devices");

            migrationBuilder.DropTable(
                name: "exercise_sessions");

            migrationBuilder.DropTable(
                name: "fatigue_assessments");

            migrationBuilder.DropTable(
                name: "hourly_health_bins");

            migrationBuilder.DropTable(
                name: "refresh_tokens");

            migrationBuilder.DropTable(
                name: "sync_batches");

            migrationBuilder.DropTable(
                name: "user_profiles");

            migrationBuilder.DropTable(
                name: "AspNetRoles");

            migrationBuilder.DropTable(
                name: "AspNetUsers");
        }
    }
}
