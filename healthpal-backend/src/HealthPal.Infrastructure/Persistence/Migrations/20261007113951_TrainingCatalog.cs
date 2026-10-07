using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace HealthPal.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class TrainingCatalog : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "exercise_catalog_items",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    name = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    english_name = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    muscle_group = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    exercise_type = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    equipment = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    instructions = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_exercise_catalog_items", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "user_exercise_favorites",
                columns: table => new
                {
                    user_id = table.Column<string>(type: "character varying(450)", maxLength: 450, nullable: false),
                    exercise_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_exercise_favorites", x => new { x.user_id, x.exercise_id });
                    table.ForeignKey(
                        name: "fk_user_exercise_favorites_asp_net_users_user_id",
                        column: x => x.user_id,
                        principalTable: "AspNetUsers",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_user_exercise_favorites_exercise_catalog_items_exercise_id",
                        column: x => x.exercise_id,
                        principalTable: "exercise_catalog_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.InsertData(
                table: "exercise_catalog_items",
                columns: new[] { "id", "english_name", "equipment", "exercise_type", "instructions", "is_active", "muscle_group", "name" },
                values: new object[,]
                {
                    { "band-row", "Resistance Band Row", "Dây kháng lực", "Strength", "Kéo khuỷu tay về sau, siết bả vai rồi trả dây chậm.", true, "back", "Kéo dây kháng lực" },
                    { "bicep-curl", "Bicep Curl", "Tạ tay", "Strength", "Giữ khuỷu tay sát thân, cuốn tạ lên rồi hạ chậm.", true, "arms", "Cuốn tay trước" },
                    { "bodyweight-squat", "Bodyweight Squat", "Không dụng cụ", "Strength", "Đẩy hông ra sau, hạ người đến mức thoải mái rồi đứng lên bằng lực chân.", true, "legs", "Squat không tạ" },
                    { "brisk-walk", "Brisk Walk", "Không dụng cụ", "Cardio", "Đi với tốc độ nhanh vừa đủ để nhịp tim tăng nhưng vẫn nói được câu ngắn.", true, "cardio", "Đi bộ nhanh" },
                    { "plank", "Plank", "Không dụng cụ", "Isometric", "Siết cơ bụng, giữ đầu-cổ-lưng-hông trên một đường thẳng.", true, "core", "Plank" },
                    { "push-up", "Push-up", "Không dụng cụ", "Strength", "Giữ thân người thẳng, hạ ngực có kiểm soát rồi đẩy trở lại.", true, "chest", "Hít đất" },
                    { "reverse-lunge", "Reverse Lunge", "Không dụng cụ", "Strength", "Bước một chân ra sau, hạ gối có kiểm soát và giữ thân người ổn định.", true, "legs", "Chùng chân ngược" },
                    { "shoulder-press", "Shoulder Press", "Tạ tay", "Strength", "Đẩy tạ lên trên đầu, không khóa cứng khuỷu tay và hạ xuống có kiểm soát.", true, "shoulder", "Đẩy vai" }
                });

            migrationBuilder.CreateIndex(
                name: "ix_exercise_catalog_items_is_active_muscle_group",
                table: "exercise_catalog_items",
                columns: new[] { "is_active", "muscle_group" });

            migrationBuilder.CreateIndex(
                name: "ix_user_exercise_favorites_exercise_id",
                table: "user_exercise_favorites",
                column: "exercise_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "user_exercise_favorites");

            migrationBuilder.DropTable(
                name: "exercise_catalog_items");
        }
    }
}
